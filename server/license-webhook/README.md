# AI Mac Optimizer — ライセンスキー自動発行 Webhook

Stripe の本番決済完了後に署名付きライセンスキーを発行し、Resend で購入者へ送信する Cloudflare Worker。
月額ライセンスは KV に保存した購読状態を `/validate` で確認し、解約・支払い失敗をアプリへ反映する。

## セットアップ

```bash
cd server/license-webhook
npm ci
npx wrangler login

npx wrangler secret put PRIVATE_KEY_B64
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put FROM_EMAIL
npx wrangler secret put STRIPE_WEBHOOK_SECRET
npm run deploy
```

本番の送信元は、Resend で認証済みの `AI Mac Optimizer <license@aimacoptimizer.com>` を使用する。
`PRIVATE_KEY_B64` は `~/.aimac_license_private_key` にある Ed25519 seed（32 byte）の base64。コードや Git へ含めない。

## Stripe Webhook の受信イベント

本番エンドポイントで次を有効にする。

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `invoice.paid`
- `customer.subscription.updated`
- `customer.subscription.deleted`

2026-07-26時点で本番エンドポイントは上記5イベントを購読済み。Worker Version `21ad5c30-2a0d-4a12-9855-b1952398ccd7` をデプロイ済み。

現在のデプロイは本番用 `STRIPE_WEBHOOK_SECRET` だけで署名検証するため、購入フローの実地確認には Stripe 本番モードを使う。テストモードのイベントは署名シークレットが異なるため、この本番エンドポイントでは受理されない。

## 処理仕様

- 初回決済は Checkout Session の `mode` で月額・買い切りを判定し、欠落時だけ金額（既定 `4,980` 円）を使用する。
- 買い切りキーは無期限、月額キーは発行から35日有効。月額は期限後も購読が active なら `/validate` で継続できる。
- `invoice.paid` は購読状態を active に戻す。更新ごとのキー再発行・メール再送は行わない。
- `customer.subscription.updated/deleted` は past_due・解約状態を KV に反映する。
- Stripe イベントが順不同でも、より新しい購読状態を優先する。

## 重複処理とエラー処理

- Checkout Session ID ごとの処理状態を KV に保存し、処理済み決済は再処理しない。
- 同じ Session ID から同じ署名キーを生成するため、同時配送や再試行でもキーが変わらない。
- Resend へ `Idempotency-Key` を付与し、同一メールの重複送信も防ぐ。
- Resend が非2xx・通信失敗・不正応答を返した場合、Webhook は `502` を返す。Stripe の再試行時に同じキー・同じメール内容で再送する。
- KV が利用できない場合は `503` とし、ライセンス発行を成功扱いにしない。`/validate` も `503` となるため、アプリは通信失敗として現在状態を維持する。

## 検証

```bash
npm test
npm run typecheck
npm audit
```

本番デプロイ後は、購入を発生させずに Worker の GET ヘルスチェックと、ダミーキーを使った `/validate` の `valid:false` を確認する。Checkout イベントの手動再送は、過去イベントが新しい冪等化記録を持たずメールを再送する可能性があるため行わない。
