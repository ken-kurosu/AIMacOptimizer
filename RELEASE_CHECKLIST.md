# AI Mac Optimizer v2.0.0 リリース手順

## ステップ1: Developer ID 証明書の取得（必須・手動）

現在「Apple Development」証明書のみ。DMG配布には「Developer ID Application」が必要。

1. https://developer.apple.com/account/resources/certificates/list を開く
2. 「+」ボタン → 「Developer ID Application」を選択
3. キーチェーンアクセスで CSR（証明書署名要求）を作成:
   - キーチェーンアクセス → 証明書アシスタント → 認証局に証明書を要求
   - メールアドレス: kurosu@i-kasa.com
   - 「ディスクに保存」を選択
4. CSR をアップロード → 証明書をダウンロード → ダブルクリックでインストール
5. 確認: ターミナルで `security find-identity -v -p codesigning | grep 'Developer ID'`

所要時間: 約10分

## ステップ2: App用パスワード作成（Notarization用・手動）

1. https://appleid.apple.com/account/manage → サインイン
2. 「アプリ用パスワード」→「アプリ用パスワードを生成」
3. ラベル: 「notarytool」
4. 生成されたパスワードをメモ（例: xxxx-xxxx-xxxx-xxxx）
5. ターミナルで保存:
   ```
   xcrun notarytool store-credentials "AIMacOptimizer"
     --apple-id kurosu@i-kasa.com
     --team-id <チームID>
     --password <アプリ用パスワード>
   ```
   ※ チームIDは developer.apple.com → Membership で確認

## ステップ3: DMGビルド＆署名

```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer
chmod +x scripts/build_dmg.sh
./scripts/build_dmg.sh
```

※ スクリプト内の DEVELOPER_ID と APPLE_ID を自分の値に書き換えてから実行

## ステップ4: Paddle アカウント作成＆商品登録

### 4-1. アカウント作成
1. https://vendors.paddle.com/signup → アカウント作成
2. ビジネス情報を入力（個人でもOK）
3. 支払い受取情報を設定

### 4-2. 商品登録
Catalog → Products → 「+ New Product」で2つ作成:

**商品1: Pro Monthly**
- Name: AI Mac Optimizer Pro (Monthly)
- Type: Subscription
- Price: ¥480/月（JPY 480）
- Billing: Monthly

**商品2: Pro Lifetime**
- Name: AI Mac Optimizer Pro (Lifetime)
- Type: One-time
- Price: ¥4,980（JPY 4980）

### 4-3. チェックアウトリンク取得
各商品の「Share」→ チェックアウトリンクをコピー

### 4-4. アプリに反映
`LicenseManager.swift` の `PurchaseConfig` を更新:
```swift
static let proMonthlyURL = "https://buy.paddle.com/product/実際のID"
static let proLifetimeURL = "https://buy.paddle.com/product/実際のID"
```

### 4-5. Webhook設定（ライセンスキー自動発行）
Paddle → Developer Tools → Webhooks で:
- URL: 自サイトのエンドポイント or Zapier/Make.com で自動化
- イベント: `transaction.completed`
- 購入完了時にライセンスキー（AIMAC-XXXX-XXXX-XXXX形式）をメールで自動送信

※ 最初は手動でキー発行でもOK。購入通知メールが届くので、それを見てキーを送る。

## ステップ5: LP（ランディングページ）のデプロイ

ファイル: `/Users/kurosuken/Desktop/AIMacOptimizer/docs/index.html`

デプロイ先の選択肢:
- **GitHub Pages**: リポジトリの docs/ フォルダを公開設定
- **Netlify**: docs/ フォルダをドラッグ&ドロップ
- **自サイト**: index.html をアップロード

LP内のダウンロードリンクをDMGの実際のURLに差し替え。

## ステップ6: 最終チェックリスト

### ビルド確認
- [ ] Xcodeでクリーンビルド成功
- [ ] DMGが正常に作成される
- [ ] DMGからアプリをインストールして起動確認

### 機能テスト
- [ ] メニューバーにメモリ%が表示される
- [ ] 3タブ（メモリ/ストレージ/ツール）+ 診断タブ切替
- [ ] メモリ最適化（ワンクリック）が動作する
- [ ] ストレージスキャン → キャッシュ削除（Pro）
- [ ] 診断 → スコア表示 → 自動修復 → 再診断
- [ ] バッテリーヘルス表示（MacBookの場合）
- [ ] アプリアンインストーラースキャン
- [ ] 通知が届く（メモリ高負荷時）
- [ ] AIチャット（APIキー設定後）
- [ ] フォント関連ファイルが保護されている

### 課金・ライセンス
- [ ] Freeユーザーの制限が正しく効く
- [ ] プロモコード適用でProになる
- [ ] ライセンスキー入力でProになる
- [ ] 設定 → アップグレードボタン → Paddle決済ページが開く
- [ ] Pro機能（ストレージ削除、AIチャット等）がアンロックされる

### セキュリティ
- [ ] `codesign -vvv` で署名検証OK
- [ ] `spctl -a -vvv` でNotarization検証OK
- [ ] Gatekeeperの警告なしで起動

### LP
- [ ] ダウンロードリンクが正しいDMGを指す
- [ ] 購入ボタンがPaddleチェックアウトに飛ぶ
- [ ] モバイルで表示崩れなし

