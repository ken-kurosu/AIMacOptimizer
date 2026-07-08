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
  LICENSES?: KVNamespace;        // ライセンス⇔購読状態の対応表（オンライン検証用）
}

// KV に保存するライセンス状態
interface LicenseRecord {
  tier: 'pro' | 'lifetime';
  status: 'active' | 'canceled' | 'past_due';
  email?: string;
  subscriptionId?: string;
  updatedAt: number;
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
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
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

// 2025-01-01 00:00:00 UTC からの日数（アプリの SignedLicense と同じ基準）
const LICENSE_EPOCH = 1_735_689_600;
// 月額キーの有効日数（更新猶予込み）。オンライン検証が主経路で、これはオフライン時のフォールバック期限。
const MONTHLY_VALID_DAYS = 35;

// 署名付きライセンスキー生成（アプリの SignedLicense.verify と同じ v2 形式）
//   message = [version(2), tier(1: 1=Pro / 2=Lifetime), expiryHi, expiryLo, nonce(2)]
//   expiry = LICENSE_EPOCH からの日数(UInt16)。0 = 無期限（買い切り）。
//   key = "AIMAC-" + base64url(message + signature(64))
function generateKey(seed: Uint8Array, tier: number): string {
  // 月額(tier=1)は今日+35日で失効。買い切り(tier=2)は無期限(0)。
  const expiryDays =
    tier === 1 ? Math.floor((Date.now() / 1000 - LICENSE_EPOCH) / 86400) + MONTHLY_VALID_DAYS : 0;
  const nonce = crypto.getRandomValues(new Uint8Array(2));
  const message = new Uint8Array([2, tier, (expiryDays >> 8) & 0xff, expiryDays & 0xff, ...nonce]);
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
    `※月額プランは、アプリがオンラインで購読状態を自動確認するため、通常このキーの貼り直しは不要です。\n` +
    `※このキーは大切に保管してください。\n— AI Mac Optimizer`;
  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env.FROM_EMAIL, to: [to], subject: 'AI Mac Optimizer ライセンスキー', text }),
  });
}

// KV 保存ヘルパ（LICENSES 未設定でも落ちないように）
async function saveRecord(env: Env, key: string, rec: LicenseRecord): Promise<void> {
  if (!env.LICENSES) return;
  await env.LICENSES.put('key:' + key, JSON.stringify(rec));
  if (rec.subscriptionId) await env.LICENSES.put('sub:' + rec.subscriptionId, key);
}
async function updateStatusBySubscription(env: Env, subId: string, status: LicenseRecord['status']): Promise<void> {
  if (!env.LICENSES) return;
  const key = await env.LICENSES.get('sub:' + subId);
  if (!key) return;
  const rec = (await env.LICENSES.get('key:' + key, 'json')) as LicenseRecord | null;
  if (!rec) return;
  rec.status = status;
  rec.updatedAt = Date.now();
  await env.LICENSES.put('key:' + key, JSON.stringify(rec));
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    // --- オンライン購読検証エンドポイント（アプリが定期的に叩く） ---
    // POST /validate  { "license_key": "AIMAC-..." }  ->  { valid, tier }
    // 購読が有効な限り valid:true を返し、アプリは Pro を自動維持する（毎月の貼り直し不要）。
    if (req.method === 'POST' && url.pathname === '/validate') {
      const bodyText = await req.text();
      let licenseKey = '';
      try { licenseKey = (JSON.parse(bodyText).license_key || '').toString(); } catch { /* ignore */ }
      if (!licenseKey) return json({ valid: false });
      const rec = env.LICENSES ? ((await env.LICENSES.get('key:' + licenseKey, 'json')) as LicenseRecord | null) : null;
      if (!rec) return json({ valid: false });
      if (rec.tier === 'lifetime') return json({ valid: true, tier: 'lifetime' });
      return json({ valid: rec.status === 'active', tier: 'pro' });
    }

    if (req.method !== 'POST') return new Response('ok'); // ヘルスチェック用

    // --- Stripe Webhook ---
    const payload = await req.text();
    const sig = req.headers.get('stripe-signature') || '';
    if (!(await verifyStripe(payload, sig, env.STRIPE_WEBHOOK_SECRET))) {
      return new Response('invalid signature', { status: 400 });
    }

    const event = JSON.parse(payload);
    const lifetimeAmount = Number(env.LIFETIME_AMOUNT || '4980');
    const seed = b64ToBytes(env.PRIVATE_KEY_B64);

    // 初回購入（買い切り・月額とも）
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const email: string | undefined = session.customer_details?.email || session.customer_email;
      const amount = Number(session.amount_total || 0);
      const tier = amount >= lifetimeAmount ? 2 : 1;
      const tierName = tier === 2 ? 'Pro (買い切り)' : 'Pro (月額)';
      const key = generateKey(seed, tier);
      const subscriptionId: string | undefined =
        typeof session.subscription === 'string' ? session.subscription : undefined;
      await saveRecord(env, key, {
        tier: tier === 2 ? 'lifetime' : 'pro',
        status: 'active',
        email,
        subscriptionId,
        updatedAt: Date.now(),
      });
      if (email) await sendEmail(env, email, key, tierName);
    }
    // 月額サブスクの更新。オンライン検証が主経路なのでキーは再発行せず、状態を active に更新するだけ。
    else if (event.type === 'invoice.paid') {
      const invoice = event.data.object;
      if (invoice.billing_reason === 'subscription_cycle' && typeof invoice.subscription === 'string') {
        await updateStatusBySubscription(env, invoice.subscription, 'active');
      }
    }
    // 解約・支払い失敗 → 状態更新（アプリは次回検証で Pro を維持しなくなる）
    else if (event.type === 'customer.subscription.deleted') {
      const sub = event.data.object;
      if (typeof sub.id === 'string') await updateStatusBySubscription(env, sub.id, 'canceled');
    } else if (event.type === 'customer.subscription.updated') {
      const sub = event.data.object;
      if (typeof sub.id === 'string') {
        const s = sub.status; // active / past_due / canceled / unpaid ...
        const mapped: LicenseRecord['status'] =
          s === 'active' || s === 'trialing' ? 'active' : s === 'past_due' ? 'past_due' : 'canceled';
        await updateStatusBySubscription(env, sub.id, mapped);
      }
    }
    return new Response('ok');
  },
};
