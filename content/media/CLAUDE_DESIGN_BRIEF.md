# Claude Design 手渡しブリーフ — オウンドメディア「Mac実測ラボ」

> このファイルは **Claude Design に貼って、メディアのビジュアルデザインを生成してもらうための仕様書**です。
> そのまま全文を渡してもよいし、「## 依頼プロンプト」だけを貼って、参考として `homepage-mockup.html` を添付する形でもOK。
> デザインの**構造・文言・トークン・クラス名**はこちらで確定済みなので、Claude Design には**"見た目の作り込み"に集中**してもらいます。出力がそのまま Astro の器（`~/Desktop/mac-jissoku-lab/`）のコンポーネントに嵌まるよう、**クラス名を固定**しています。

---

## 0. まずこれを渡す（依頼プロンプト・コピペ用）

> あなたはプロダクトデザイナーです。macOS周辺の技術メディア「**Mac実測ラボ**」のビジュアルデザインを作ってください。
> トーンは「**盛らない・測る・信頼できる**」。Apple/macOS周辺の上質さで、けばけばしくしない。数字と計測(Before/After)が主役です。
> 以下3画面を、**それぞれ単一の自己完結HTML**（CSS/JSインライン・外部依存なし・画像はSVG/CSSで代用）で作ってください。**ライト/ダーク両対応**（`prefers-color-scheme` ＋ `:root[data-theme]`）、レスポンシブ（横スクロールを起こさない）、日本語。
> 1. メディアトップページ
> 2. 記事ページ（テンプレート）
> 3. カテゴリ一覧ページ
> **重要な制約**: 下記「デザイントークン」の色を使い、**"実測グリーン"は実際に計測した数値にだけ**使うこと。各コンポーネントの**クラス名は下記指定どおり厳守**（後段のシステムに嵌め込むため）。添付の `homepage-mockup.html` を下敷きに、より完成度の高いビジュアルへ引き上げてください（レイアウト構造とクラス名は踏襲）。

---

## 1. これは何のメディアか（背景）

- **メディア名**: Mac実測ラボ（英: Mac Jissoku Lab）。タグライン: **「盛らない。測る。Macを軽くする実測メディア」**
- **運営元**: Macメニューバーアプリ「AI Mac Optimizer」の開発チーム（メディア→アプリDLが最終導線）
- **編集の核 = 「実測で正直」**: 「〇GB空くはず」という予測は書かない。実機で計測した Before/After の**実数だけ**を出す。これが競合(一般論記事・盛る系クリーナー)に対する堀。
- **読者**: ①Macが重い/容量パンパンで困っている一般ユーザー、②サブスク疲れのクリエイター、③自動化したい開発者。
- **既存の姉妹サイト（トーンの連続性を保つ）**: LP `https://aimacoptimizer.github.io/`（同じく Apple 的な上質・実測グリーンを使用）

---

## 2. デザイントークン（厳守）

CSS変数で定義し、ライト/ダーク両方を用意すること。**実測グリーンは"計測済みの数値"専用**（見出しやボタンには使わない）。

```css
:root{
  --bg:#f5f5f7; --surface:#ffffff; --surface-2:#fafafc;
  --text:#1d1d1f; --text-2:#55555c; --text-3:#86868b; --line:#e3e3e8;
  --accent:#0a66c2; --accent-ink:#ffffff;        /* リンク/アクション(落ち着いた青) */
  --measured:#1a7f4e; --measured-bg:#e8f5ee;      /* ★実測値専用グリーン */
  --before:#c9c9cf; --after:#34a06b;              /* Before/Afterバー */
  --badge-bg:#eef4fb;
  --radius:14px;
  --shadow:0 1px 2px rgba(0,0,0,.04), 0 8px 24px rgba(0,0,0,.06);
  color-scheme:light dark;
}
@media (prefers-color-scheme:dark){ :root{
  --bg:#0e0e10; --surface:#1a1a1e; --surface-2:#202024;
  --text:#f2f2f4; --text-2:#b9b9c1; --text-3:#7f7f88; --line:#2c2c32;
  --accent:#5aa4e8; --accent-ink:#0b1522;
  --measured:#4fc98b; --measured-bg:#14301f;
  --before:#45454d; --after:#34a06b; --badge-bg:#1b2733;
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px rgba(0,0,0,.35);
}}
/* 手動トグル用に :root[data-theme="light"] / [data-theme="dark"] の同値も定義すること */
```

- **フォント**: `-apple-system, BlinkMacSystemFont, "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", sans-serif`
- **数値は等幅＋タブラー**: 計測値・GB・%・日付には `.num { font-family: ui-monospace,"SF Mono",Menlo,monospace; font-variant-numeric: tabular-nums; }`
- **角丸14px・柔らかい影**、境界は`--line`の1px。装飾は控えめ、余白でリズムを作る。
- **ブランドマーク**: メーター(ゲージ)モチーフのSVG（角丸四角＋半円ゲージ＋針）。`homepage-mockup.html` のものを流用可。

---

## 3. 実測ビジュアル言語（このメディアの"顔"・全画面共通の部品）

以下は複数画面で再利用するので、**同じクラス名・同じ見た目**で作ること。

| 部品 | クラス名 | 役割・見た目 |
|---|---|---|
| 実測チップ | `.measured-chip` | 「✓ 前後の実測差」等。`--measured-bg`背景＋`--measured`文字の丸ピル。**計測済みの証** |
| Before/Afterバー | `.bar` > `i.fill-before` / `i.fill-after` | 横棒。beforeはグレー、afterは緑。幅%で表現 |
| 計測環境の開示ボックス | `.measure-env` | 記事/カードに必ず添える「M2 MacBook Air / macOS 15.5 / 2026-07-20計測」。控えめグレー、等幅 |
| 実測デルタ | `.delta` | 「−19.3 GB」の大きい緑数字（実測値専用色） |

> ルール: **数値を出す場所には必ず計測環境(`.measure-env`)を併記**。数値の色に緑を使うのは"実測済み"のときだけ。予測・一般値には緑を使わない（グレー/通常色）。

---

## 4. 画面①：メディアトップページ

`homepage-mockup.html` の構成を踏襲し、完成度を上げる。セクションと固定クラス名:

1. **ヘッダー** `header` … ブランド(`.brand` + `.brand-mark`SVG)、グローバルナビ`nav.global`（Macが重い/ストレージ/メモリと速度/比較と選び方/実測レポート/アプリ）、テーマ切替`#themeToggle`。sticky・半透明blur。
2. **ヒーロー** `.hero` … 左: eyebrow`.hero-eyebrow`「● すべての記事に実機計測のBefore/After」、h1「盛らない。測る。/ だから、Macは軽くなる。」、リード文、CTA 2つ（`.btn.btn-primary`「実測記事を読む」/ `.btn.btn-ghost`「今月の定点計測を見る」）。右: **実測パネル**`.hero-panel`（ストレージ最適化の Before/After ＋ `.delta`＋`.measured-chip`＋`.measure-env`）。
3. **編集方針ストリップ** `.principles`（3枚: 予測値ではなく実測値 / 安全側の手順だけ / 計測環境を全開示）。
4. **注目記事** `#featured` … `.card-grid` に `.article-card` × 3。各カードに Before/Afterミニバー(`.card-visual`)＋カテゴリタグ`.cat-tag`＋見出し＋抜粋＋`.card-meta`（`.measured-chip`＋更新日）。
5. **実測データ特集(Labs)** `.labs` … 左に見出し「アプリキャッシュ肥大ランキング(月次定点)」、右に横棒チャート`.labs-chart`（Chrome/Adobe CC/Cursor/Slack/Spotify…）＋`.measure-env`＋注記。
6. **カテゴリ** `#pillars` … `.pillar-grid` に5ピラー`.pillar`（🐢Macが重い / 💾ストレージ / ⚡メモリと速度 / ⚖️比較と選び方 / 🔬実測レポート）。各記事数バッジ。
7. **アプリCTA** `#app .app-cta` … 「判断の難しさを、AI Mac Optimizerが肩代わり」＋チェックリスト＋DLボタン＋価格注記(¥480/¥4,980)＋右にメニューバー風モック`.app-visual`。
8. **フッター** `footer` … ブランド説明・カテゴリ・ラボについて・運営開示（"AI Mac Optimizerの開発チームが運営"を明記＝E-E-A-T）。

※ 文言は `homepage-mockup.html` の実データをそのまま使用（ダミー禁止）。

---

## 5. 画面②：記事ページ（テンプレート）※新規に設計が必要

トップに無い新画面。以下の要素を、読みやすい記事レイアウトで。**本文の可読性**が最優先。

- **パンくず** `.breadcrumb`（Mac実測ラボ › ストレージを空ける › 記事名）
- **記事ヘッダー** `.article-header` … カテゴリタグ`.cat-tag`、h1、公開/更新日（`.num`）、そして**この記事の計測環境ボックス**`.measure-env`（機種/チップ/macOS/計測日）を目立つ位置に。ブランドの信頼装置なので必ず上部に。
- **本文タイポグラフィ** `.article-body` … h2/h3、段落(line-height 1.8前後)、リスト、コード`<code>`、引用。
  - **注意ボックス** `.callout`（2種: `.callout-safe`=消してよい/緑寄り、`.callout-warn`=触ってはいけない/警告色）。安全性を色で即伝える。
  - **Before/After比較ブロック** `.compare-block`（本文中に埋め込む実測結果。`.bar`＋`.delta`＋`.measure-env`）。
  - **インライン実測チップ** `.measured-chip` を文中で使える体裁。
- **本文中CTA（3型）** — 位置で `utm_content` を変える想定なので、3つ作る:
  - `.cta-inline`（記事途中の軽いテキストリンク型）
  - `.cta-card`（セクション終わりのカード型・DLボタン付き）
  - `.cta-end`（記事末尾の強めのバナー型）
- **FAQ** `.faq` … アコーディオン（`<details>`ベースでJS最小）。
- **関連記事** `.related` … `.article-card` を2〜3枚。
- **フッター** はトップと共通`footer`。

移植元の本文例として `content/seo/01-mac-system-data.md`（記事1）を使うと具体イメージが湧く。

---

## 6. 画面③：カテゴリ一覧ページ

- パンくず`.breadcrumb`、カテゴリヘッダー`.category-header`（絵文字＋カテゴリ名＋一言説明＋記事数）、`.card-grid`に`.article-card`を縦に並べる、必要ならページネーション`.pager`。トップ/記事とヘッダー・フッター・カード体裁を共通化。

---

## 7. 出力してほしい形（重要・Astroへの取り込み条件）

- **3画面それぞれ単一HTML**（`top.html` / `article.html` / `category.html` 相当）。自己完結（外部CDN/フォント/画像なし）。
- **クラス名は本ブリーフ指定を厳守**（`.hero` `.article-card` `.measured-chip` `.labs-chart` `.pillar` `.app-cta` `.callout-safe/warn` `.compare-block` `.measure-env` 等）。→ こちらでCSSを Astro コンポーネントへ抽出し、既存の器のマークアップに当てるだけで反映できる。
- **共通部品（ヘッダー/フッター/カード/CTA/実測部品）は3画面で完全に同一の見た目**にすること（コンポーネント化するため）。
- ライト/ダーク両対応、レスポンシブ、基本的なa11y（コントラスト、フォーカス可視、`aria-label`、見出し階層）。

---

## 8. この後の流れ（黒須さん向けメモ）

1. 本ブリーフ（＋`homepage-mockup.html`を参考添付）を **Claude Design に渡す** → 3画面のHTMLを受け取る
2. 受け取ったら私（Claude Code）に共有 → **CSSを Astro の器（`~/Desktop/mac-jissoku-lab/`）のコンポーネントへ統合**（クラス名を揃えてあるので差し込みで当たる）
3. `npm run build` で確認 → デプロイ（`aimacoptimizer.github.io/blog/` もしくは独自ドメイン統合。ドメインは別途決定）

> デザインで迷ったら「**この数字は実測か？ → Yesなら緑、Noなら緑を使わない**」を判断基準に。これがメディアの一貫性を守る唯一のルールです。
