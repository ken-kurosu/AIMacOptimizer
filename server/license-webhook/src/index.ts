import * as ed25519 from '@noble/ed25519';
import { sha256 } from '@noble/hashes/sha2.js';
import { sha512 } from '@noble/hashes/sha2.js';

// noble-ed25519 v2 に sha512 を供給（Cloudflare Workers でも動く純JS実装）
ed25519.etc.sha512Sync = (...m: Uint8Array[]) => sha512(ed25519.etc.concatBytes(...m));

export interface Env {
  STRIPE_WEBHOOK_SECRET: string;
  PRIVATE_KEY_B64: string;
  RESEND_API_KEY: string;
  FROM_EMAIL: string;
  LIFETIME_AMOUNT?: string;
  LICENSES?: KVNamespace;
}

interface LicenseRecord {
  tier: 'pro' | 'lifetime';
  status: 'active' | 'canceled' | 'past_due';
  email?: string;
  subscriptionId?: string;
  statusEventCreated: number;
  updatedAt: number;
}

interface SubscriptionState {
  status: LicenseRecord['status'];
  eventCreated: number;
  updatedAt: number;
}

interface CheckoutEventRecord {
  status: 'prepared' | 'processed';
  stripeEventId: string;
  checkoutSessionId: string;
  licenseKey: string;
  email: string;
  tier: LicenseRecord['tier'];
  resendEmailId?: string;
  updatedAt: number;
}

interface StripeEvent {
  id: string;
  type: string;
  created: number;
  data: { object: Record<string, unknown> };
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
  }
}

function b64urlFromBytes(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64ToBytes(b64: string): Uint8Array {
  try {
    const bin = atob(b64.trim());
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    throw new HttpError(500, 'license signing key is invalid');
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new HttpError(400, `missing ${field}`);
  }
  return value;
}

function requireKV(env: Env): KVNamespace {
  if (!env.LICENSES) throw new HttpError(503, 'license storage is unavailable');
  return env.LICENSES;
}

function parseStripeEvent(payload: string): StripeEvent {
  let value: unknown;
  try {
    value = JSON.parse(payload);
  } catch {
    throw new HttpError(400, 'invalid JSON');
  }
  if (!value || typeof value !== 'object') throw new HttpError(400, 'invalid event');
  const candidate = value as Partial<StripeEvent>;
  if (
    typeof candidate.id !== 'string' ||
    typeof candidate.type !== 'string' ||
    typeof candidate.created !== 'number' ||
    !candidate.data ||
    typeof candidate.data.object !== 'object' ||
    candidate.data.object === null
  ) {
    throw new HttpError(400, 'invalid event');
  }
  return candidate as StripeEvent;
}

// Stripe Webhook 署名検証（HMAC-SHA256）。鍵ローテーション時の複数 v1 署名にも対応する。
async function verifyStripe(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  if (!secret || !sigHeader) return false;
  let timestamp = '';
  const signatures: string[] = [];
  for (const part of sigHeader.split(',')) {
    const separator = part.indexOf('=');
    if (separator < 0) continue;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (key === 't') timestamp = value;
    if (key === 'v1') signatures.push(value);
  }
  const timestampNumber = Number(timestamp);
  if (!Number.isFinite(timestampNumber) || signatures.length === 0) return false;
  if (Math.abs(Date.now() / 1000 - timestampNumber) > 300) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(`${timestamp}.${payload}`));
  const expected = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return signatures.some((signature) => {
    if (signature.length !== expected.length) return false;
    let difference = 0;
    for (let i = 0; i < expected.length; i++) {
      difference |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
    }
    return difference === 0;
  });
}

const LICENSE_EPOCH = 1_735_689_600;
const MONTHLY_VALID_DAYS = 35;

// Checkout Session ID から nonce を決定的に作るため、Stripe の再試行や同時配送でも同じキーになる。
function generateKey(seed: Uint8Array, tier: number, sessionId: string, eventCreated: number): string {
  if (seed.length !== 32) throw new HttpError(500, 'license signing key is invalid');
  const createdDay = Math.floor((eventCreated - LICENSE_EPOCH) / 86400);
  const expiryDays = tier === 1 ? createdDay + MONTHLY_VALID_DAYS : 0;
  if (expiryDays < 0 || expiryDays > 0xffff) throw new HttpError(500, 'license expiry is out of range');
  const nonce = sha256(new TextEncoder().encode(`aimac-license-v2:${sessionId}`)).slice(0, 2);
  const message = new Uint8Array([2, tier, (expiryDays >> 8) & 0xff, expiryDays & 0xff, ...nonce]);
  const signature = ed25519.sign(message, seed);
  const keyData = new Uint8Array(message.length + signature.length);
  keyData.set(message, 0);
  keyData.set(signature, message.length);
  return 'AIMAC-' + b64urlFromBytes(keyData);
}

async function sendEmail(
  env: Env,
  to: string,
  key: string,
  tierName: string,
  idempotencyKey: string,
): Promise<string> {
  if (!env.RESEND_API_KEY || !env.FROM_EMAIL) throw new HttpError(500, 'email configuration is unavailable');
  const text =
    `ご購入ありがとうございます（${tierName}）。\n\n` +
    `以下のライセンスキーを、アプリの「設定 → ライセンス → ライセンスキー」に貼り付けて有効化してください。\n\n` +
    `${key}\n\n` +
    `※月額プランは、アプリがオンラインで購読状態を自動確認するため、通常このキーの貼り直しは不要です。\n` +
    `※このキーは大切に保管してください。\n— AI Mac Optimizer`;
  let response: Response;
  try {
    response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': idempotencyKey,
      },
      body: JSON.stringify({
        from: env.FROM_EMAIL,
        to: [to],
        subject: 'AI Mac Optimizer ライセンスキー',
        text,
      }),
    });
  } catch {
    throw new HttpError(502, 'email provider is unavailable');
  }
  if (!response.ok) {
    // API キーや本文を外部応答・ログへ含めない。Stripe に非2xxを返して安全に再試行させる。
    throw new HttpError(502, `email delivery failed (${response.status})`);
  }
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    throw new HttpError(502, 'email provider returned an invalid response');
  }
  const emailId = (body as { id?: unknown }).id;
  if (typeof emailId !== 'string' || emailId.length === 0) {
    throw new HttpError(502, 'email provider returned an invalid response');
  }
  return emailId;
}

async function saveRecord(env: Env, key: string, record: LicenseRecord): Promise<void> {
  const kv = requireKV(env);
  let merged = record;
  if (record.subscriptionId) {
    const latest = (await kv.get(`substate:${record.subscriptionId}`, 'json')) as SubscriptionState | null;
    if (latest && latest.eventCreated >= record.statusEventCreated) {
      merged = {
        ...record,
        status: latest.status,
        statusEventCreated: latest.eventCreated,
        updatedAt: Date.now(),
      };
    }
  }
  await kv.put(`key:${key}`, JSON.stringify(merged));
  if (record.subscriptionId) await kv.put(`sub:${record.subscriptionId}`, key);
}

async function updateStatusBySubscription(
  env: Env,
  subscriptionId: string,
  status: LicenseRecord['status'],
  eventCreated: number,
): Promise<void> {
  const kv = requireKV(env);
  const existingState = (await kv.get(`substate:${subscriptionId}`, 'json')) as SubscriptionState | null;
  if (!existingState || eventCreated >= existingState.eventCreated) {
    const state: SubscriptionState = { status, eventCreated, updatedAt: Date.now() };
    await kv.put(`substate:${subscriptionId}`, JSON.stringify(state));
  }

  const key = await kv.get(`sub:${subscriptionId}`);
  if (!key) return;
  const record = (await kv.get(`key:${key}`, 'json')) as LicenseRecord | null;
  if (!record || eventCreated < (record.statusEventCreated ?? 0)) return;
  record.status = status;
  record.statusEventCreated = eventCreated;
  record.updatedAt = Date.now();
  await kv.put(`key:${key}`, JSON.stringify(record));
}

async function processCheckout(event: StripeEvent, env: Env): Promise<Response> {
  const kv = requireKV(env);
  const session = event.data.object;
  const sessionId = requireString(session.id, 'checkout session id');
  const emailValue = (session.customer_details as { email?: unknown } | undefined)?.email ?? session.customer_email;
  const email = requireString(emailValue, 'customer email');
  const paymentStatus = session.payment_status;
  if (paymentStatus !== undefined && paymentStatus !== 'paid' && paymentStatus !== 'no_payment_required') {
    return json({ received: true, pending: true });
  }

  const eventStorageKey = `event:checkout:${sessionId}`;
  const existing = (await kv.get(eventStorageKey, 'json')) as CheckoutEventRecord | null;
  if (existing?.status === 'processed') return json({ received: true, duplicate: true });

  const lifetimeAmount = Number(env.LIFETIME_AMOUNT || '4980');
  if (!Number.isFinite(lifetimeAmount) || lifetimeAmount <= 0) {
    throw new HttpError(500, 'lifetime amount is invalid');
  }
  const amount = Number(session.amount_total || 0);
  const isLifetime = session.mode === 'payment' || (session.mode !== 'subscription' && amount >= lifetimeAmount);
  const tierNumber = isLifetime ? 2 : 1;
  const tier: LicenseRecord['tier'] = isLifetime ? 'lifetime' : 'pro';
  const tierName = isLifetime ? 'Pro (買い切り)' : 'Pro (月額)';
  const key = existing?.licenseKey ?? generateKey(b64ToBytes(env.PRIVATE_KEY_B64), tierNumber, sessionId, event.created);
  const subscriptionId = typeof session.subscription === 'string' ? session.subscription : undefined;
  const prepared: CheckoutEventRecord = {
    status: 'prepared',
    stripeEventId: event.id,
    checkoutSessionId: sessionId,
    licenseKey: key,
    email,
    tier,
    updatedAt: Date.now(),
  };
  await kv.put(eventStorageKey, JSON.stringify(prepared));
  await saveRecord(env, key, {
    tier,
    status: 'active',
    email,
    subscriptionId,
    statusEventCreated: event.created,
    updatedAt: Date.now(),
  });

  const resendEmailId = await sendEmail(env, email, key, tierName, `stripe-checkout-${sessionId}`);
  await kv.put(
    eventStorageKey,
    JSON.stringify({ ...prepared, status: 'processed', resendEmailId, updatedAt: Date.now() }),
  );
  return json({ received: true });
}

async function processStatusEvent(event: StripeEvent, env: Env): Promise<Response> {
  const kv = requireKV(env);
  const eventStorageKey = `event:stripe:${event.id}`;
  if (await kv.get(eventStorageKey)) return json({ received: true, duplicate: true });

  const object = event.data.object;
  if (event.type === 'invoice.paid') {
    if (object.billing_reason === 'subscription_cycle' && typeof object.subscription === 'string') {
      await updateStatusBySubscription(env, object.subscription, 'active', event.created);
    }
  } else if (event.type === 'customer.subscription.deleted') {
    const subscriptionId = requireString(object.id, 'subscription id');
    await updateStatusBySubscription(env, subscriptionId, 'canceled', event.created);
  } else if (event.type === 'customer.subscription.updated') {
    const subscriptionId = requireString(object.id, 'subscription id');
    const stripeStatus = requireString(object.status, 'subscription status');
    const mapped: LicenseRecord['status'] =
      stripeStatus === 'active' || stripeStatus === 'trialing'
        ? 'active'
        : stripeStatus === 'past_due'
          ? 'past_due'
          : 'canceled';
    await updateStatusBySubscription(env, subscriptionId, mapped, event.created);
  }
  await kv.put(eventStorageKey, JSON.stringify({ type: event.type, processedAt: Date.now() }));
  return json({ received: true });
}

async function handleValidate(req: Request, env: Env): Promise<Response> {
  const kv = requireKV(env);
  let body: unknown;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return json({ valid: false }, 400);
  }
  const licenseKey = (body as { license_key?: unknown }).license_key;
  if (typeof licenseKey !== 'string' || licenseKey.length === 0) return json({ valid: false });
  const record = (await kv.get(`key:${licenseKey}`, 'json')) as LicenseRecord | null;
  if (!record) return json({ valid: false });
  if (record.tier === 'lifetime') return json({ valid: true, tier: 'lifetime' });
  return json({ valid: record.status === 'active', tier: 'pro' });
}

export async function handleRequest(req: Request, env: Env): Promise<Response> {
  try {
    const url = new URL(req.url);
    if (req.method === 'POST' && url.pathname === '/validate') return await handleValidate(req, env);
    if (req.method !== 'POST') return new Response('ok');

    const payload = await req.text();
    const signature = req.headers.get('stripe-signature') || '';
    if (!(await verifyStripe(payload, signature, env.STRIPE_WEBHOOK_SECRET))) {
      throw new HttpError(400, 'invalid signature');
    }
    const event = parseStripeEvent(payload);
    if (event.type === 'checkout.session.completed' || event.type === 'checkout.session.async_payment_succeeded') {
      return await processCheckout(event, env);
    }
    return await processStatusEvent(event, env);
  } catch (error) {
    if (error instanceof HttpError) return json({ error: error.publicMessage }, error.status);
    return json({ error: 'internal server error' }, 500);
  }
}

export default { fetch: handleRequest };
