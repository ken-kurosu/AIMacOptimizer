import * as ed25519 from '@noble/ed25519';
import { sha512 } from '@noble/hashes/sha2.js';

// noble-ed25519 v2 に sha512 を供給（Cloudflare Workers でも動く純JS実装）
ed25519.etc.sha512Sync = (...m: Uint8Array[]) => sha512(ed25519.etc.concatBytes(...m));

export interface Env {
  STRIPE_WEBHOOK_SECRET: string; // Stripe Webhook 署名シークレット (whsec_...)
  PRIVATE_KEY_B64: string;       // Ed25519 秘密鍵 seed(32byte) の base64（~/.aimac_license_private_key の中身）
  RESEND_API_KEY: string;        // Resend API キー
  FROM_EMAIL: string;            // 例: "AI Mac Optimizer <license@yourdomain.com>"
  LIFETIME_AMOUNT?: string;      // 買い切りの金額(円)。これ以上なら Lifetime。既定 4980
}

// ---- helpers ----
function b64urlFromBytes(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Stripe Webhook 署名検証（HMAC-SHA256）
async function verifyStripe(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  const parts: Record<string, string> = {};
  for (const kv of sigHeader.split(',')) {
    const [k, v] = kv.split('=');
    if (k && v) parts[k.trim()] = v.trim();
  }
  const t = parts['t'];
  const v1 = parts['v1'];
  if (!t || !v1) return false;
  // 5分以上前のものは拒否（リプレイ対策）
  if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return false;

  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode(`${t}.${payload}`));
  const macHex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  if (macHex.length !== v1.length) return false;
  let diff = 0;
  for (let i = 0; i < macHex.length; i++) diff |= macHex.charCodeAt(i) ^ v1.charCodeAt(i);
  return diff === 0;
}

// 署名付きライセンスキー生成（アプリの SignedLicense.verify と同じ形式）
//   message = [version(1), tier(1: 1=Pro / 2=Lifetime), nonce(4)]
//   key = "AIMAC-" + base64url(message + signature(64))
function generateKey(seed: Uint8Array, tier: number): string {
  const nonce = crypto.getRandomValues(new Uint8Array(4));
  const message = new Uint8Array([1, tier, ...nonce]);
  const sig = ed25519.sign(message, seed);
  const keyData = new Uint8Array(message.length + sig.length);
  keyData.set(message, 0);
  keyData.set(sig, message.length);
  return 'AIMAC-' + b64urlFromBytes(keyData);
}

async function sendEmail(env: Env, to: string, key: string, tierName: string): Promise<void> {
  const text =
    `ご購入ありがとうございます（${tierName}）。\n\n` +
    `以下のライセンスキーを、アプリの「設定 → ライセンス → ライセンスキー」に貼り付けて有効化してください。\n\n` +
    `${key}\n\n` +
    `※このキーは大切に保管してください。\n— AI Mac Optimizer`;
  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env.FROM_EMAIL, to: [to], subject: 'AI Mac Optimizer ライセンスキー', text }),
  });
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method !== 'POST') return new Response('ok'); // ヘルスチェック用
    const payload = await req.text();
    const sig = req.headers.get('stripe-signature') || '';
    if (!(await verifyStripe(payload, sig, env.STRIPE_WEBHOOK_SECRET))) {
      return new Response('invalid signature', { status: 400 });
    }

    const event = JSON.parse(payload);
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const email: string | undefined = session.customer_details?.email || session.customer_email;
      const amount = Number(session.amount_total || 0);
      const lifetimeAmount = Number(env.LIFETIME_AMOUNT || '4980');
      const tier = amount >= lifetimeAmount ? 2 : 1;
      const tierName = tier === 2 ? 'Pro (買い切り)' : 'Pro (月額)';
      if (email) {
        const seed = b64ToBytes(env.PRIVATE_KEY_B64);
        const key = generateKey(seed, tier);
        await sendEmail(env, email, key, tierName);
      }
    }
    return new Response('ok');
  },
};
