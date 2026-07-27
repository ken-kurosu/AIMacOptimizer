# AIMacOptimizer リリース残作業と手順

最終更新: 2026-07-26 / 対象ブランチ: `main`（build15 / v2.1.12）

現状: 一般販売前の必須作業は完了。Mac版アプリは**署名・Apple公証済みDMGをGitHub Releasesで配布中**。
LPは `https://aimacoptimizer.com/` でHTTPS公開済み。課金WebhookはCloudflare Workersで本番稼働し、購入・メール到達・Pro化・解約後のFree化まで実地確認済み。

---

## 1. Stripe の確認（最優先・黒須さんのダッシュボード操作）

アプリに埋め込み済みの Payment Link:
- 月額 `¥480/月`: `https://buy.stripe.com/4gMeV6bN6fS61hv6XqgYU00`
- 買い切り `¥4,980`: `https://buy.stripe.com/00w9AMbN65dsbW90z2gYU01`

### 確認手順
1. Stripe ダッシュボードを **本番モード(Live)** に切替
2. **Payment Links** で上記2本が存在し、
   - 月額が `¥480/月`のサブスク、買い切りが `¥4,980`の一回払いになっているか
   - 商品名・税設定・請求先メール収集(顧客メール)が有効か（キー送付に必須）
3. Webhook は Checkout Session の `mode`（subscription/payment）でプランを判定。`mode` 欠落時のみ `LIFETIME_AMOUNT="4980"` をフォールバックに使用

> 私に検証させる場合は、**読み取り専用APIキー(`rk_...`)** を渡してもらえれば Payment Link/商品/金額をAPIで突合します。

---

## 2. ライセンス自動発行 Webhook のデプロイ（Cloudflare Workers + Resend）

決済完了 → 署名付きライセンスキーを自動生成してメール送付する仕組み。コードは `server/license-webhook/` に完成済み。

### 事前に用意（黒須さん）
- Cloudflare アカウント（無料）
- Resend アカウント（無料枠100通/日）＋送信元ドメイン認証 or 検証済み送信元アドレス

### デプロイ手順（`!` を付けてこのセッションで実行すれば一緒に進められます）
```bash
cd ~/AIMacOptimizer/server/license-webhook
npm install
npx wrangler login                              # Cloudflareにログイン(ブラウザ)

# シークレット設定（プロンプトに値を貼る）
npx wrangler secret put PRIVATE_KEY_B64         # ← `cat ~/.aimac_license_private_key` の中身(今の新しい秘密鍵)
npx wrangler secret put RESEND_API_KEY          # ← Resend の API キー
npx wrangler secret put FROM_EMAIL              # 例: "AI Mac Optimizer <license@あなたのドメイン>"

npx wrangler deploy                             # → https://aimac-license-webhook.<account>.workers.dev が発行
```

### Stripe 側の Webhook 設定（上でURLが出た後）
1. Stripe → Developers → Webhooks → **Add endpoint**
2. Endpoint URL = 上で発行された Workers の URL
3. 受信イベント = **`checkout.session.completed`**、**`checkout.session.async_payment_succeeded`**、**`invoice.paid`**、**`customer.subscription.updated`**、**`customer.subscription.deleted`**
4. 表示される **Signing secret（`whsec_...`）** をコピー →
   ```bash
   cd ~/AIMacOptimizer/server/license-webhook
   npx wrangler secret put STRIPE_WEBHOOK_SECRET
   npx wrangler deploy
   ```

### 動作
- 初回決済 → プラン判定 → 署名キー `AIMAC-...` を生成 → 購入者メールへ一度だけ送付
- 月額更新(`invoice.paid`/subscription_cycle) → 購読状態を active に更新（キー再発行・再送なし）
- 解約・支払い遅延 → KV の購読状態を更新し、アプリの次回オンライン確認で Free 化
- Checkout Session ID と Resend の冪等キーで重複発行・重複メールを防止。メール失敗時は非2xxで Stripe に再試行させる
- ※秘密鍵は本セッションでローテーション済み（旧鍵は無効）。Workerには**新しい鍵**を入れること

---

## 3. 月額プランのライブ検証（本番で月額を売る前に必須）

本番用署名シークレットだけをWorkerに設定しているため、テストモードではなく本番モードで確認済み。
1. ✅ 月額購入 → 初回キーがメール到達 → アプリでPro化
2. ✅ 購入後の解約・返金
3. ✅ Worker修正版を本番デプロイ（Version `21ad5c30-2a0d-4a12-9855-b1952398ccd7`）
   - GETヘルスチェック `200 ok`
   - 不正署名POST `400 invalid signature`
   - ダミーキーの `/validate` `200 {"valid":false}`
4. ✅ Stripe本番Webhookを5イベント購読へ更新
5. ✅ 解約済みキーの `/validate` が `valid:false` を返すことを確認
6. ✅ build15実機で `pro → free`、無効化記録、猶予削除を確認

---

## 4. LP（ランディングページ）

- 設計書: `docs/LP_DESIGN_BRIEF.md`（競合調査＋構成＋デザイン＋アニメ＋コピー＋アセット）
- ✅ 本番LPを `https://aimacoptimizer.com/` で公開（GitHub Pages、HTTPS強制）
- ✅ apex / www / 旧 `aimacoptimizer.github.io` の301、canonical、OG、JSON-LD、sitemap、robotsを新ドメインへ統一
- ✅ GitHub Organizationでドメイン所有権を検証し、Pages乗っ取りを防止
- ✅ Google Search ConsoleのドメインプロパティをDNS検証し、サイトマップ3ページを正常送信
- ✅ 旧 `ken-kurosu.github.io/AIMacOptimizer/` の転送スタブも新ドメインへ更新
- オウンドメディアは `https://aimacoptimizer.com/blog/` 前提でソースURLを統一済み。デザイン・コンテンツ完成後にLPリポへ統合して公開する

---

## 5. その後の改善候補（v1.1・任意）

- 診断の重いI/Oをバックグラウンド化（実行中のUIフリーズ解消）
- 初回オンボーディング＋権限(通知/オートメーション)の状態表示・誘導
- ストレージの「大物」検出強化（ollamaモデル/iOSシミュレータ/アプリ別CachedData/トップレベル内訳）
- 診断/advisorの長文の英中i18n（主要UIは対応済み、長文detailは日本語残）
- アプリ自身のメモリ footprint 削減（常駐で~300MBはやや高め）
- 公開前の最終: 署名鍵の管理（`~/.aimac_license_private_key` のバックアップ、`.retired-*` の保管/削除判断）

---

## 現在の到達点（済み）
- ✅ v2.1.12 / build15の署名・Apple公証・ステープル済みDMGをGitHub Releasesで公開
- ✅ 課金モデル確定（Free=現在の実測/手動整理/診断/ローカルAI相談、Pro=自動化＋履歴/詳細レポート）
- ✅ 署名ライセンス(v2・有効期限対応)＋鍵ローテーション
- ✅ 解放量の表示=実測（過大表示の撲滅）／通知の抑制修正／日英中i18n
- ✅ Webhook本番稼働・購入からメール到達まで実地確認済み
- ✅ 重複処理防止・メール失敗時再試行・順不同イベント・解約反映を実装し、自動テスト5件成功・本番再デプロイ済み
- ✅ 本番購入、キーのメール到達、Pro化、解約・返金、build15でのFree復帰を実地確認済み
- ✅ LPを `https://aimacoptimizer.com/` で公開し、独自ドメイン・HTTPS・SEO移行を完了
