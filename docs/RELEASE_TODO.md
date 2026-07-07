# AIMacOptimizer リリース残作業と手順

最終更新: 2026-07-07 / 対象ブランチ: `quality/warnings-fix`(= origin/main)

現状: Mac版アプリは**署名・公証済みDMGが配布可能**（`build/release/AIMacOptimizer-v2.0.0.dmg`）。
残っているのは主に**課金の配線(Stripe + Webhook)**、**LP実装/公開**、**月額のライブ検証**。

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
3. **金額の整合**: Webhook は `amount >= 4980` を買い切り、未満を月額と判定（`wrangler.toml` の `LIFETIME_AMOUNT="4980"`）。¥4,980と¥480ならこの閾値でOK

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
3. 受信イベント = **`checkout.session.completed`** と **`invoice.paid`**（月額更新用）
4. 表示される **Signing secret（`whsec_...`）** をコピー →
   ```bash
   cd ~/AIMacOptimizer/server/license-webhook
   npx wrangler secret put STRIPE_WEBHOOK_SECRET
   npx wrangler deploy
   ```

### 動作
- 初回決済 → 金額でtier判定 → 署名キー `AIMAC-...` を生成 → 購入者メールへ送付
- 月額更新(`invoice.paid`/subscription_cycle) → 毎月あらたな35日キーを再発行して送付
- ※秘密鍵は本セッションでローテーション済み（旧鍵は無効）。Workerには**新しい鍵**を入れること

---

## 3. 月額プランのライブ検証（本番で月額を売る前に必須）

キーの有効期限(オフライン)は実装・検証済みだが、サブスクの更新/解約の実挙動はライブ確認が必要。
1. Stripe **テストモード**で月額を購入 → 初回キーがメール到達・アプリで Pro になる
2. `invoice.paid`(subscription_cycle) のテストイベント送信 → 更新キーがメール到達
3. サブスク解約 → 期限(35日)到達後にアプリが自動で Free に戻る

**これらが確認できるまでは、アプリ内/LP の月額導線は出さず「買い切りのみ」を推奨。**（買い切りは期限問題なし）

---

## 4. LP（ランディングページ）

- 設計書: `docs/LP_DESIGN_BRIEF.md`（競合調査＋構成＋デザイン＋アニメ＋コピー＋アセット）
- 実装は **Claude Design** で行い、コードで納品 → このリポの `docs/` に反映（GitHub Pages 公開想定）
- 実装前に埋める確定情報（設計書 第9章の要確認事項）:
  - 独自ドメイン有無 / DMGダウンロードURL（GitHub Releases 等）/ 上記Stripeリンク / 税込表記 / 最小macOS要件(現状 macOS 13+) / プロダクト名表記(`AIMacOptimizer` か `AI Mac Optimizer`)
- 既存 `docs/index.html` は旧内容（機能・料金が古い）。新LPで置換予定
- `docs/tokushoho.html`（特定商取引法）の記載内容も最新の価格/事業者情報に更新

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
- ✅ 署名・公証済みDMG（Gatekeeper警告なし配布可能）
- ✅ 課金モデル確定（Free=最適化/診断/AI相談 無制限、Pro=ストレージ削除＋スケジュール）
- ✅ 署名ライセンス(v2・有効期限対応)＋鍵ローテーション
- ✅ 解放量の表示=実測（過大表示の撲滅）／通知の抑制修正／日英中i18n
- ✅ Webhookコード完成（未デプロイ）
- ✅ LP設計書完成（未実装）
