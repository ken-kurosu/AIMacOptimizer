@AGENTS.md

# Slide Studio — 開発引き継ぎメモ

AIスライドデザインツール。経緯・設計判断・検証手順をここに残す。README.md も併読すること。

## プロジェクトの目的(オーナーとの合意事項)

- pptx/Googleスライドのデザイン制約を脱し、**GPT image系の画像生成品質のデザイン**で、かつ**全パーツが後から編集可能**(テキスト打ち直し・移動・リンク埋め込み)で、**最終的にリンク付きPDF**にできるツール
- デザイン品質の基準は「GPT image 2 のポン出し」。**カード(surface塗り+枠+角丸)の羅列はオーナーが明確に拒否** — エディトリアルな構成(大判タイポ、ゴースト数字、全面塗り、はみ出す円、罫線区切り)を使うこと
- 採用アーキテクチャ: **カンプ先行パイプライン** = 画像モデルで完成デザインの一枚絵を作り、それを編集可能な層に分解する
- レイアウト方式: ハイブリッド(生成はテンプレ/計画経由で崩れ防止、配置後は絶対座標で自由編集)
- 生成パイプラインは**OpenAIで統一**(デザイン整合性のため。オーナー指定)。構造化生成エンジンのみClaude

## 現状(2026-06-11時点)

完成済み:
- エディタ一式(ドラッグ+スナップ、リサイズ、インライン編集、Undo/Redo、テーマトークン、リンク、JSON入出力、localStorage永続化)
- PDF書き出し(/print + ブラウザ印刷)。**外部リンク・ページ内リンクがPDFに保持されることを検証済み**
- エディトリアル版テンプレート(lib/templates.ts)とデモ生成(lib/mock.ts)
- image2カンプ先行パイプライン(lib/image2Pipeline.ts): 計画(GPT)→カンプ(gpt-image)→分解(GPTビジョン)→2層デッキ

**未検証**: image2パイプラインの実機実行。前セッションは api.openai.com がネットワークポリシーでブロックされていた(`curl https://api.openai.com/v1/models` が "Host not in allowlist" を返したら同じ状態)。オーナーが環境設定で `api.openai.com` を許可し `OPENAI_API_KEY` を環境変数に入れる予定。

## 次セッションの最優先タスク: image2パイプラインの実機検証

1. `curl -s https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" | head -c 300` で到達とキーを確認
2. `cd slide-studio && npm install && npm run build && npm run start -- -p 3344`(バックグラウンドは `setsid ... &` で起動。`&`だけだと死ぬことがある)
3. `curl http://localhost:3344/api/generate` → `{"openai":true,...}` を確認
4. `curl -X POST http://localhost:3344/api/generate -H 'Content-Type: application/json' -d '{"topic":"...","pages":6,"engine":"image2"}'` で生成(1〜3分)
5. 下記のヘッドレスブラウザ検証手順で全ページをスクリーンショットし、**目視で品質確認**(テキストの可読性・コントラスト・はみ出し・配置の重なり)。問題があれば lib/image2Pipeline.ts のプロンプト(PLAN_SYSTEM / VISION_SYSTEM)を調整して反復
6. PDF書き出しまで通す(画像背景がPDFに正しく入るか、解像度が十分か確認)

既知の調整候補: ビジョン配置の精度が低ければ「カンプに文字ゾーンの薄いガイド枠を描かせる」「配置後にスクショ→再批評の1ループ追加」。解像度不足なら quality を high に。

## 開発・検証手順(この環境固有のノウハウ)

- ビルド: `npm run build`(Next 16 / Turbopack。AGENTS.mdの通り node_modules/next/dist/docs/ に同梱ドキュメントあり)
- 本番起動: `(setsid npm run start -- -p 3344 > /tmp/next.log 2>&1 < /dev/null &)`
- **ヘッドレスブラウザ**: Playwright CDNはブロックされているが、**/opt/pw-browsers/chromium-1194/chrome-linux/chrome にChromiumがプリインストール済み**。`/tmp で npm i playwright` して `chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] })`
- スライドの目視検証: `/print` を開き `.print-slide` 要素を1枚ずつ `locator.screenshot()` → Readツールで画像を見る
- PDF検証: `page.pdf({ width: '13.333in', height: '7.5in', printBackground: true, margin: 0 })` → PDFバイナリ内の `/Subtype /Link` `/URI` `/Dest` をカウントしてリンク保持を確認
- デッキをlocalStorageに注入してテストするキー: `slide-studio-deck`、形式 `{ state: { deck, selectedSlideId }, version: 0 }`

## ハマりどころ(再発防止)

- zustand persist は**状態変更時にしか書き込まない** → Editor.tsx のマウント時に `useEditor.setState((s) => ({ deck: s.deck }))` で初期保存している。消さないこと
- `select()` で `editingElementId` を消すとインライン編集の確定(blur)前に入力が失われる → select では消さない設計
- 生成画像をbase64でデッキに入れるとlocalStorage上限(~5MB)を超える → `.assets/` に保存し `/api/assets/<id>` で配信する方式を維持
- gpt-image系は16:9を出せない(3:2) → sharpで中央16:9を切り出し(lib/image2Pipeline.ts)
- モデルIDはハードコードしない: OpenAIは `/v1/models` から自動選択(lib/openai.ts)。Anthropicは claude-opus-4-8

## ロードマップ(オーナーと合意済みの順序)

1. image2パイプライン実機検証・品質チューニング ← いまここ
2. パーツ層の分解(カンプから装飾を切り抜き/個別生成して透過PNGの可動パーツに)
3. レンダリング→ビジョン批評→修正のループ
4. ページ単位・要素単位の再生成
5. サーバーサイドPDF(Playwright + pdf-lib)
