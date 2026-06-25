# AI Mac Optimizer — macOS アプリケーション リリースガイド

このドキュメントは、AI Mac Optimizer を DMG 形式でビルド、署名、公証し、macOS ユーザーに配布するための完全なガイドです。

---

## 📋 目次

1. [事前準備](#事前準備)
2. [Developer ID Application 証明書の取得](#developer-id-application-証明書の取得)
3. [アプリ固有パスワードの作成](#アプリ固有パスワードの作成)
4. [ビルドスクリプトの実行](#ビルドスクリプトの実行)
5. [署名と公証の検証](#署名と公証の検証)
6. [DMG の配布](#dmg-の配布)
7. [トラブルシューティング](#トラブルシューティング)

---

## 事前準備

### 必要なもの

以下が揃っていることを確認してください:

- **Apple Developer Program メンバーシップ**
  - 個人または組織のメンバーシップが必要です
  - https://developer.apple.com/programs/ で申し込み
  - 年間 $99 USD かかります

- **macOS 13 以上**
  - ビルドマシンは macOS 13 以上である必要があります
  - Xcode 14.3 以上を推奨

- **Xcode コマンドラインツール**
  ```bash
  xcode-select --install
  ```

- **有効な Apple ID**
  - developer.apple.com にサインインできること
  - 2要素認証が設定されていること（必須）

### 現在の環境確認

```bash
# Xcode バージョン確認
xcodebuild -version

# macOS バージョン確認
sw_vers

# インストール済み証明書を確認
security find-identity -p codesigning -v
```

---

## Developer ID Application 証明書の取得

Developer ID Application 証明書は、macOS ユーザーが安全にアプリケーションをダウンロード・実行できるようにするため、Apple によるコード署名を証明するものです。

### ステップ 1: Apple Developer Account にログイン

1. **Certificates, IDs & Profiles** にアクセス
   - https://developer.apple.com/account/resources/certificates/list にアクセス
   - Apple ID でログイン（2要素認証が求められる場合があります）

2. **左側メニューで「Certificates」を選択**
   - 「Certificates, IDs & Profiles」 > 「Certificates」

### ステップ 2: 新しい証明書リクエストを作成

1. **「+」ボタンをクリック**
   - ページの右上付近にある青い「+」をクリック

2. **証明書タイプを選択**
   - 「Developer ID Application」を選択
   - ❌ **注意**: 「iOS Development」や「Apple Development」ではなく、必ず「Developer ID Application」を選択してください
   - 「Continue」をクリック

3. **署名リクエストファイル（CSR）をアップロード**

   a) **ローカルマシンで CSR を生成**
   ```bash
   # Keychain Access.app を開く
   open -a "Keychain Access"
   ```

   b) **Keychain Access で CSR を生成**
   - メニュー: 「Keychain Access」 > 「Certificate Assistant」 > 「Request a Certificate from a Certificate Authority...」
   - 入力項目:
     - **Common Name**: あなた名（例: `KEN KUROSU`）
     - **Email Address**: Apple ID メールアドレス
     - **CA Email**: 空白のままでOK
     - **Request is**: 「Saved to disk」を選択
   - 「Continue」をクリック
   - ファイル名を設定（例: `CertificateSigningRequest.certSigningRequest`）
   - 保存

   c) **Apple Developer サイトで CSR をアップロード**
   - 「Choose File」をクリック
   - 生成した `.certSigningRequest` ファイルを選択
   - 「Continue」をクリック

### ステップ 3: 証明書をダウンロード

1. **証明書ファイルをダウンロード**
   - 「Download」をクリック
   - ファイル名: `developerID_application.cer` など
   - 保存先: ダウンロードフォルダ

2. **証明書をインストール**
   - ダウンロードした `.cer` ファイルをダブルクリック
   - Keychain Access が自動的に起動して、証明書をインポート
   - 画面指示に従うだけで OK

3. **インストール確認**
   ```bash
   security find-identity -p codesigning -v | grep "Developer ID Application"
   ```
   
   以下のような出力が表示されれば、インストール成功です:
   ```
   1) XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX "Developer ID Application: KEN KUROSU (MQ7UQ6PT46)"
   ```

---

## アプリ固有パスワードの作成

アプリ固有パスワードは、Notary Service に Apple ID とパスワードを送信せずに認証するための、セキュアな認証メカニズムです。

### ステップ 1: Apple ID アカウントページへアクセス

1. **appleid.apple.com にアクセス**
   - https://appleid.apple.com
   - Apple ID でサインイン
   - 2要素認証を完了

2. **「Sign-In and Security」をクリック**
   - ページの左側メニューから「Sign-In and Security」を選択

### ステップ 2: アプリ固有パスワードを生成

1. **「App-Specific Passwords」セクションを見つける**
   - 「Sign-In and Security」ページの下の方にあります

2. **「Generate password」（パスワード生成）をクリック**
   - または表の右側の「+」をクリック

3. **アプリケーション名を入力**
   - 例: `notarytool` または `AI Mac Optimizer`
   - デバイスを選択（例: `This Mac (macOS)`）
   - 「Create」をクリック

4. **パスワードをコピー**
   - 生成されたパスワードが表示されます
   - ⚠️ このパスワードは一度だけ表示されます
   - テキストエディタに一時的に保存

### ステップ 3: Notarytool に認証情報を保存

```bash
# Keychain に認証情報を保存
xcrun notarytool store-credentials "AIMacOptimizer" \
  --apple-id your-email@example.com \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password"
```

**パラメータの説明:**
- `"AIMacOptimizer"`: プロフィール名（任意、スクリプトで使用される名前）
- `--apple-id`: Apple ID のメールアドレス（2要素認証が有効なアカウント）
- `--team-id`: Team ID（下記参照）
- `--password`: 生成したアプリ固有パスワード

### Team ID の確認方法

```bash
# 方法 1: Apple Developer サイト
# https://developer.apple.com/account → Membership → Team ID を確認

# 方法 2: コマンドラインで確認
security find-identity -p codesigning -v | grep "Developer ID Application"
# 出力例: 1) XXXX "Developer ID Application: KEN KUROSU (MQ7UQ6PT46)"
#                                          括弧内が Team ID
```

### 認証情報の確認

保存に成功したかどうか確認:

```bash
# Keychain に保存された認証情報を確認
xcrun notarytool history --keychain-profile "AIMacOptimizer" --page-size 1
```

エラーなく結果が返されれば、認証情報が正常に保存されています。

---

## ビルドスクリプトの実行

### スクリプトの場所

```
/Users/kurosuken/Desktop/AIMacOptimizer/scripts/build_dmg.sh
```

### 実行方法

#### 方法 1: パラメータで証明書を指定（推奨）

```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer

./scripts/build_dmg.sh \
  "Developer ID Application: KEN KUROSU (MQ7UQ6PT46)" \
  "your-email@example.com"
```

#### 方法 2: 環境変数で指定

```bash
export DEVELOPER_ID="Developer ID Application: KEN KUROSU (MQ7UQ6PT46)"
export APPLE_ID="your-email@example.com"

cd /Users/kurosuken/Desktop/AIMacOptimizer
./scripts/build_dmg.sh
```

#### 方法 3: Keychain から自動検出（最も簡単）

```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer
./scripts/build_dmg.sh
```

スクリプトが自動的に Keychain から Developer ID を検出します。

### スクリプト実行時のステップ

スクリプトは以下の 7 つのステップを自動実行します:

```
ステップ 1: システム要件の確認
  ├─ Xcode のインストール確認
  ├─ codesign ツールの確認
  ├─ xcrun/notarytool の確認
  ├─ hdiutil の確認
  └─ プロジェクトファイルの確認

ステップ 2: 証明書の確認
  ├─ Developer ID Application 証明書をキーチェーンから検索
  └─ 見つからない場合はエラーメッセージを表示

ステップ 3: xcodebuild でのビルド
  ├─ Release 構成でコンパイル
  ├─ .app バンドルを生成
  └─ リソースを配置

ステップ 4: コード署名
  ├─ ネストされたフレームワーク・ライブラリに署名
  ├─ メインアプリケーションに署名
  ├─ ハードニング化されたランタイムを有効化
  └─ 署名を検証

ステップ 5: DMG ディスクイメージの作成
  ├─ アプリケーションを DMG にコピー
  ├─ Applications フォルダへのシンボリックリンクを作成
  ├─ インストール手順の README を作成
  └─ 圧縮して DMG ファイルを生成

ステップ 6: DMG ファイルの署名
  ├─ DMG ファイル自体に Developer ID で署名
  └─ 署名を検証

ステップ 7: Apple Notary Service による公証
  ├─ DMG を Apple に送信
  ├─ ウイルス・マルウェア検査を待つ
  └─ 公証チケットをステープル
```

### 実行結果

実行が成功すると、以下のファイルが生成されます:

```
/Users/kurosuken/Desktop/AIMacOptimizer/build/release/
├── AIMacOptimizer.app/         ← コンパイル済みアプリケーション
├── DerivedData/                ← ビルド中間ファイル
└── AIMacOptimizer-latest.dmg   ← 配布用 DMG ファイル
```

### よくある問題と対処法

**Q: エラー: "Developer ID Application 証明書が見つかりません"**

A: 以下の手順で証明書をインストールしてください:
1. https://developer.apple.com/account/resources/certificates/list にアクセス
2. 「Developer ID Application」証明書をダウンロード
3. ダウンロードしたファイルをダブルクリック
4. もう一度スクリプトを実行

---

**Q: エラー: "Keychain 認証情報が見つかりません"**

A: Notarytool 認証情報をセットアップしてください:
```bash
xcrun notarytool store-credentials "AIMacOptimizer" \
  --apple-id your-email@example.com \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password"
```

---

**Q: ビルド時間が長すぎます**

A: これは正常です。初回ビルドは 3～10 分かかる場合があります。
コンパイルキャッシュが作成されると、次のビルドは高速になります。

---

## 署名と公証の検証

### アプリケーションの署名を確認

```bash
# アプリケーションの署名情報を表示
codesign --display --verbose /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer.app
```

以下の情報が表示されることを確認:
- `Authority=Developer ID Application`
- `Runtime Version` が存在する（ハードニング化されたランタイム）

### DMG ファイルの署名を確認

```bash
# DMG ファイルが署名されているか確認
codesign --verify /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer-latest.dmg
```

### 公証チケットを確認

```bash
# DMG が公証されているか確認（ステープルされているか）
xcrun stapler validate /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer-latest.dmg
```

以下の出力が表示されれば、公証完了です:
```
The staple on this file is valid on this system.
```

### インターネット経由での検証

別のネットワークやマシンから DMG をダウンロードして、以下を実行:

```bash
# DMG をマウント
open ~/Downloads/AIMacOptimizer-latest.dmg

# アプリケーションを起動（Gatekeeper による検証）
# → Gatekeeper の警告が表示されないことを確認
```

---

## DMG の配布

### ファイルの準備

1. **DMG ファイルをコピー**
   ```bash
   cp /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer-latest.dmg ~/Desktop/
   ```

2. **ファイルをテスト**
   - 別のマシンから DMG をダウンロード
   - マウント（ダブルクリック）
   - アプリケーションを起動
   - Gatekeeper の警告が表示されず、正常に起動することを確認

### ウェブサイトでの公開

1. **ウェブサーバーに DMG をアップロード**
   ```bash
   # 例: sftp でサーバーにアップロード
   sftp user@example.com
   put /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer-latest.dmg
   ```

2. **ダウンロードリンクをページに追加**
   ```html
   <a href="https://example.com/downloads/AIMacOptimizer-latest.dmg">
     AI Mac Optimizer をダウンロード
   </a>
   ```

3. **HTTPS を使用**
   - ⚠️ **重要**: ダウンロードリンクは必ず HTTPS を使用してください
   - Apple では、署名・公証されたアプリケーションは HTTPS 経由での配布を推奨しています

### 署名・公証状態の確認

ユーザーが DMG をダウンロード後、以下のコマンドで検証できることを伝える:

```bash
# デベロッパー情報を表示
spctl -a -vvv -t open --context context:primary-signature ~/Downloads/AIMacOptimizer-latest.dmg

# 期待される出力:
# valid on disk
# satisfies its Designated Requirement
```

---

## トラブルシューティング

### よくあるエラーと解決策

#### 1. "xcodebuild not found"

```bash
# 解決策: Xcode コマンドラインツールをインストール
xcode-select --install
```

#### 2. "Developer ID Application certificate not found"

```bash
# 原因: 証明書がキーチェーンにインストールされていない
# 解決策:
# 1. https://developer.apple.com/account/resources/certificates/list にアクセス
# 2. Developer ID Application 証明書をダウンロード
# 3. ダウンロードしたファイルをダブルクリック
```

#### 3. "Code signing failed: denied"

```bash
# 原因: キーチェーンのロック状態
# 解決策: キーチェーンをロック解除
security unlock-keychain
```

#### 4. "Notarization failed: Invalid credentials"

```bash
# 原因: アプリ固有パスワードが間違っている
# 解決策:
# 1. appleid.apple.com で新しいパスワードを生成
# 2. 古い認証情報を削除: xcrun notarytool delete-credentials --keychain-profile "AIMacOptimizer"
# 3. 新しい認証情報を保存: xcrun notarytool store-credentials ...
```

#### 5. "The specified item could not be found in the keychain"

```bash
# 原因: Notarytool 認証情報が保存されていない
# 解決策: 認証情報を保存
xcrun notarytool store-credentials "AIMacOptimizer" \
  --apple-id your-email@example.com \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password"
```

### ログファイルの確認

詳細なビルドログ:
```bash
# ビルドログを確認
tail -100 /Users/kurosuken/Desktop/AIMacOptimizer/build/release/*.log
```

### サポート情報

問題が解決しない場合:

1. **Apple Developer Support**
   - https://developer.apple.com/support/
   - フォーラム・チケット対応

2. **Xcode ドキュメント**
   - https://developer.apple.com/xcode/
   - Code Signing, Notarization ガイド

3. **Apple Developer Forum**
   - https://forums.developer.apple.com/
   - 開発者コミュニティ

---

## セキュリティに関する注意

### アプリ固有パスワードの管理

- ⚠️ アプリ固有パスワードを git リポジトリに保存しない
- ⚠️ 他のユーザーに共有しない
- ✅ Keychain に安全に保存（このスクリプトが自動処理）

### 証明書の更新

Developer ID Application 証明書の有効期限:
- **5年間**（更新日から）
- 更新が必要になったら、同じプロセスで新しい証明書を申請

### プライベートキーの保護

秘密鍵は Keychain に安全に保存されます:
```bash
# キーチェーン内の秘密鍵を確認（自動処理）
security find-identity -p codesigning -v
```

---

## まとめ

このガイドで説明した手順に従うことで:

✅ Apple Developer Program に登録
✅ Developer ID Application 証明書を取得
✅ アプリ固有パスワードをセットアップ
✅ build_dmg.sh スクリプトを実行
✅ DMG を作成・署名・公証
✅ ユーザーに安全に配布

以上が完了します。署名・公証されたアプリケーションは、ユーザーが初回起動時に Gatekeeper の警告を見ることなく、安全に実行できます。

---

**最終更新**: 2026 年 3 月 14 日
**バージョン**: 2.0.0
