import { beforeEach, describe, expect, it, vi } from 'vitest';
import { handleRequest, type Env } from './index';

class MemoryKV {
  readonly values = new Map<string, string>();

  async get(key: string, type?: string): Promise<unknown> {
    const value = this.values.get(key) ?? null;
    if (value !== null && type === 'json') return JSON.parse(value);
    return value;
  }

  async put(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }
}

const webhookSecret = 'whsec_test';

function makeEnv(kv: MemoryKV): Env {
  return {
    STRIPE_WEBHOOK_SECRET: webhookSecret,
    PRIVATE_KEY_B64: btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
    RESEND_API_KEY: 're_test',
    FROM_EMAIL: 'AI Mac Optimizer <license@aimacoptimizer.com>',
    LIFETIME_AMOUNT: '4980',
    LICENSES: kv as unknown as KVNamespace,
  };
}

async function stripeRequest(event: Record<string, unknown>, env: Env): Promise<Response> {
  const payload = JSON.stringify(event);
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(webhookSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(`${timestamp}.${payload}`));
  const signature = [...new Uint8Array(mac)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return handleRequest(
    new Request('https://worker.example/webhook', {
      method: 'POST',
      headers: { 'stripe-signature': `t=${timestamp},v1=${signature}` },
      body: payload,
    }),
    env,
  );
}

function checkoutEvent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'evt_checkout_1',
    type: 'checkout.session.completed',
    created: Math.floor(Date.now() / 1000),
    data: {
      object: {
        id: 'cs_live_1',
        mode: 'subscription',
        payment_status: 'paid',
        amount_total: 480,
        customer_details: { email: 'buyer@example.com' },
        subscription: 'sub_1',
      },
    },
    ...overrides,
  };
}

function successfulResend(id = 'email_1'): Response {
  return new Response(JSON.stringify({ id }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('license webhook', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('sends one email when Stripe delivers the same checkout more than once', async () => {
    const kv = new MemoryKV();
    const resend = vi.fn().mockResolvedValue(successfulResend());
    vi.stubGlobal('fetch', resend);
    const env = makeEnv(kv);

    const first = await stripeRequest(checkoutEvent(), env);
    const duplicateEvent = checkoutEvent({ id: 'evt_checkout_duplicate' });
    const second = await stripeRequest(duplicateEvent, env);

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    await expect(second.json()).resolves.toMatchObject({ duplicate: true });
    expect(resend).toHaveBeenCalledTimes(1);
    const eventRecord = JSON.parse(kv.values.get('event:checkout:cs_live_1')!);
    expect(eventRecord.status).toBe('processed');
  });

  it('returns an error on email failure and safely retries with the same key and idempotency key', async () => {
    const kv = new MemoryKV();
    const resend = vi
      .fn()
      .mockResolvedValueOnce(new Response('temporary failure', { status: 500 }))
      .mockResolvedValueOnce(successfulResend('email_retry'));
    vi.stubGlobal('fetch', resend);
    const env = makeEnv(kv);

    const failed = await stripeRequest(checkoutEvent(), env);
    const retried = await stripeRequest(checkoutEvent({ id: 'evt_checkout_retry' }), env);

    expect(failed.status).toBe(502);
    expect(retried.status).toBe(200);
    expect(resend).toHaveBeenCalledTimes(2);
    const firstRequest = resend.mock.calls[0][1] as RequestInit;
    const secondRequest = resend.mock.calls[1][1] as RequestInit;
    expect(firstRequest.body).toBe(secondRequest.body);
    expect((firstRequest.headers as Record<string, string>)['Idempotency-Key']).toBe('stripe-checkout-cs_live_1');
    expect((secondRequest.headers as Record<string, string>)['Idempotency-Key']).toBe('stripe-checkout-cs_live_1');
    const eventRecord = JSON.parse(kv.values.get('event:checkout:cs_live_1')!);
    expect(eventRecord.status).toBe('processed');
    expect(eventRecord.resendEmailId).toBe('email_retry');
  });

  it('invalidates a monthly license after a subscription deletion event', async () => {
    const kv = new MemoryKV();
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(successfulResend()));
    const env = makeEnv(kv);
    await stripeRequest(checkoutEvent(), env);
    const licenseKey = kv.values.get('sub:sub_1')!;

    const canceled = await stripeRequest(
      {
        id: 'evt_cancel_1',
        type: 'customer.subscription.deleted',
        created: Math.floor(Date.now() / 1000) + 1,
        data: { object: { id: 'sub_1' } },
      },
      env,
    );
    const validation = await handleRequest(
      new Request('https://worker.example/validate', {
        method: 'POST',
        body: JSON.stringify({ license_key: licenseKey }),
      }),
      env,
    );

    expect(canceled.status).toBe(200);
    await expect(validation.json()).resolves.toEqual({ valid: false, tier: 'pro' });
  });

  it('preserves a newer cancellation when Stripe events arrive out of order', async () => {
    const kv = new MemoryKV();
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(successfulResend()));
    const env = makeEnv(kv);
    const now = Math.floor(Date.now() / 1000);

    await stripeRequest(
      {
        id: 'evt_cancel_first',
        type: 'customer.subscription.deleted',
        created: now,
        data: { object: { id: 'sub_1' } },
      },
      env,
    );
    await stripeRequest(checkoutEvent({ created: now - 60 }), env);
    const licenseKey = kv.values.get('sub:sub_1')!;
    const validation = await handleRequest(
      new Request('https://worker.example/validate', {
        method: 'POST',
        body: JSON.stringify({ license_key: licenseKey }),
      }),
      env,
    );

    await expect(validation.json()).resolves.toEqual({ valid: false, tier: 'pro' });
  });

  it('fails closed when KV storage is missing', async () => {
    const env = { ...makeEnv(new MemoryKV()), LICENSES: undefined };
    const response = await handleRequest(
      new Request('https://worker.example/validate', {
        method: 'POST',
        body: JSON.stringify({ license_key: 'AIMAC-test' }),
      }),
      env,
    );

    expect(response.status).toBe(503);
  });
});
