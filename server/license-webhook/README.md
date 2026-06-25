# AI Mac Optimizer — ライセンスキー自動発行 Webhook（Cloudflare Workers）

Stripe で決済が完了したら、署名付きライセンスキーを自動生成して購入者へメール送信する。
サーバーレス（Cloudflare Workers 無料枠）＋ Resend（メール）で、実質ランニングコスト0。

アプリ側は埋め込んだ公開鍵でオフライン検証するため、ここで作るキーは偽造不可。
（ローカル手動発行 `scripts/sign_license.swift` と同じ鍵・同じ形式。互換性は検証済み）

## 必要なもの（黒須さんが用意）
- Cloudflare アカウント（無料）
- Resend アカウント（無料枠100通/日）＋送信元ドメイン認証（または検証済みアドレス）
- Stripe アカウント（既存）

## デプロイ手順

```bash
cd server/license-webhook
npm install
npx wrangler login            # Cloudflare にログイン

# シークレットを設定（プロンプトで値を貼り付け）
npx wrangler secret put PRIVATE_KEY_B64        # ~/.aimac_license_private_key の中身（base64の秘密鍵seed）
npx wrangler secret put RESEND_API_KEY         # Resend の API キー
npx wrangler secret put FROM_EMAIL             # 例: "AI Mac Optimizer <license@あなたのドメイン>"
# STRIPE_WEBHOOK_SECRET は Webhook 登録後に取得して設定（下記）

npx wrangler deploy          # → https://aimac-license-webhook.<account>.workers.dev が発行される
```

## Stripe 側の設定
1. Stripe ダッシュボード → Developers → Webhooks → Add endpoint
2. Endpoint URL = 上で発行された Workers の URL
3. 受信イベント = `checkout.session.completed`
4. 作成後に表示される **Signing secret (whsec_...)** をコピー
5. `npx wrangler secret put STRIPE_WEBHOOK_SECRET` で設定し、再度 `npx wrangler deploy`

## 動作
- 決済完了 → Stripe が Workers に通知 → 署名検証 → 金額で tier 判定
  （`amount_total >= 4980` 円なら買い切り、それ未満は月額。`wrangler.toml` の `LIFETIME_AMOUNT` で調整可）
- 署名付きキー `AIMAC-...` を生成 → 購入者のメールへ Resend で送信

## テスト
- Stripe ダッシュボードの Webhook 画面から「Send test webhook」で `checkout.session.completed` を送信して確認。
- 届いたキーをアプリの 設定 → ライセンス に貼ると Pro になる。

## セキュリティ注意
- `PRIVATE_KEY_B64` は秘密鍵。Workers の Secret にのみ置き、コードやGitに含めない。
- 本番公開前に鍵ペアを一度ローテーション（再生成→アプリの公開鍵差し替え→この Secret も更新）するとより安全。
