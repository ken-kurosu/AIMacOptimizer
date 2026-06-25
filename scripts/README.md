# 📦 AI Mac Optimizer — ビルド・リリース スクリプト

このディレクトリには、AI Mac Optimizer を macOS で開発・ビルド・リリースするためのスクリプトが含まれています。

---

## 📂 ファイル一覧

### 🎯 メインスクリプト

#### `build_dmg.sh` ⭐ 推奨
**完全な DMG ビルド・署名・公証スクリプト**

- **機能:**
  - xcodebuild でのビルド
  - Developer ID Application 証明書による署名
  - ハードニング化されたランタイムの有効化
  - DMG ディスクイメージの作成（ドラッグ&ドロップレイアウト）
  - DMG ファイルの署名
  - Apple Notary Service での公証
  - 公証チケットのステープル

- **使用方法:**
  ```bash
  ./build_dmg.sh
  ```
  または
  ```bash
  ./build_dmg.sh "Developer ID Application: ..." "email@example.com"
  ```

- **出力:**
  - `/build/release/AIMacOptimizer.app` ← コンパイル済みアプリケーション
  - `/build/release/AIMacOptimizer-latest.dmg` ← 配布用 DMG

- **所要時間:** 5～15 分（ネットワーク速度による）

- **言語:** Bash（日本語コメント完備）

---

### 📚 ドキュメント

#### `QUICK_START.md` ⭐ 初めての方向け
**初回セットアップと実行方法の最小版**

- **内容:**
  - Developer ID 証明書の取得方法（1 回目のみ）
  - Notarytool 認証情報の設定（1 回目のみ）
  - 毎回の実行方法
  - よくあるエラーと解決方法

- **読む時間:** 5 分

---

#### `RELEASE_GUIDE.md` ⭐ 完全ガイド
**詳細な手順書・トラブルシューティング・セキュリティ情報**

- **内容:**
  - 事前準備チェックリスト
  - Developer ID Application 証明書の取得（スクリーンショット付き）
  - Apple ID のアプリ固有パスワード生成
  - ビルドスクリプトの詳細説明
  - 署名・公証の検証方法
  - DMG の配布方法
  - トラブルシューティング（10+ パターン）
  - セキュリティに関する注意

- **読む時間:** 20～30 分

- **対象:** 本格的な配布を考えている方

---

### 🔧 その他のスクリプト

#### `build_release.sh`
**従来の Release ビルドスクリプト**

- **注:** `build_dmg.sh` が推奨されます。このスクリプトも利用可能ですが、メンテナンスは `build_dmg.sh` で行われています。

---

#### `generate_icon.sh`
**アプリケーションアイコンの生成スクリプト**

- **用途:** App Store や Finder で表示される icns ファイル生成
- **利用シーン:** デザイン変更時など

---

## 🚀 クイック実行

### 初回セットアップ（5 分）

```bash
# 1. 証明書を取得（developer.apple.com）
#    → Developer ID Application を申請・ダウンロード・インストール

# 2. Notarytool 認証情報を設定
xcrun notarytool store-credentials "AIMacOptimizer" \
  --apple-id your-email@example.com \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password"

# 確認
security find-identity -p codesigning -v | grep "Developer ID"
```

### 毎回の実行（10～15 分）

```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer
./scripts/build_dmg.sh
```

### 成果物の確認

```bash
# ビルト検証
ls -lh build/release/*.dmg
xcrun stapler validate build/release/AIMacOptimizer-latest.dmg
```

---

## 📋 必要な環境

### システム要件

- **macOS 13 以上**
- **Xcode 14.3 以上**（または Xcode コマンドラインツール）
- **有効な Apple Developer Program メンバーシップ**
  - 年間 $99 USD
  - 2要素認証が有効な Apple ID

### ネットワーク

- **インターネット接続**（Notary Service 通信用）
  - 初回ビルド: 100～500 MB ダウンロード
  - 公証アップロード: 50～500 MB（アプリサイズによる）

### ディスク容量

- **ビルド作業用:** 5～10 GB（一時ファイル）
- **成果物:** 200 MB～1 GB（アプリ + DMG）

---

## 📖 ステップバイステップガイド

### Step 1: 最小限の準備（初回のみ）

1. `QUICK_START.md` を読む（5 分）
2. Developer ID 証明書を取得（10～30 分）
3. Notarytool 認証情報を設定（5 分）

### Step 2: ビルド実行

```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer
./scripts/build_dmg.sh
```

スクリプトがすべてを自動処理します。

### Step 3: 検証

```bash
# スクリプトが最後に検証を実行
# または手動で確認:
xcrun stapler validate build/release/AIMacOptimizer-latest.dmg
```

### Step 4: 配布

DMG ファイルをウェブサイトでホスト。
署名・公証されているため、ユーザーは警告なく実行可能です。

---

## 🔍 スクリプトの動作フロー

```
build_dmg.sh 実行
     ↓
【ステップ 1】システム要件チェック
     ├─ Xcode インストール確認
     ├─ codesign ツール確認
     ├─ xcrun/notarytool 確認
     ├─ hdiutil 確認
     └─ プロジェクトファイル確認
     ↓
【ステップ 2】証明書確認
     ├─ Keychain から Developer ID を検索
     └─ 見つからない場合は警告
     ↓
【ステップ 3】xcodebuild でビルド
     ├─ Release 構成でコンパイル
     └─ .app バンドル生成
     ↓
【ステップ 4】コード署名
     ├─ フレームワーク/ライブラリに署名
     ├─ メインアプリに署名
     ├─ ハードニング化ランタイム有効
     └─ 署名検証
     ↓
【ステップ 5】DMG 作成
     ├─ アプリをコピー
     ├─ Applications シンボリックリンク作成
     ├─ README ファイル作成
     └─ DMG 圧縮生成
     ↓
【ステップ 6】DMG に署名
     ├─ DMG ファイル署名
     └─ 署名検証
     ↓
【ステップ 7】Notary Service で公証
     ├─ Keychain から認証情報を取得
     ├─ DMG を Apple にアップロード
     ├─ ウイルス検査を待つ
     ├─ 公証チケット受取
     └─ チケットをステープル
     ↓
✅ 完了 - DMG は配布可能
```

---

## 🛠️ トラブルシューティング

### よくある問題

| 状況 | 対応 |
|------|------|
| `xcodebuild not found` | `xcode-select --install` |
| `Developer ID 証明書が見つからない` | developer.apple.com で証明書取得 |
| `Keychain 認証情報が見つからない` | `xcrun notarytool store-credentials ...` |
| ビルド時間が長い | 初回は正常（キャッシュ作成中）。次回は高速化 |
| 公証が失敗する | インターネット接続、認証情報を確認 |

### 詳細なトラブルシューティング

**→ RELEASE_GUIDE.md の「トラブルシューティング」セクションを参照**

---

## 📝 スクリプトのカスタマイズ

### バージョン番号の変更

```bash
# 環境変数で指定
export VERSION="2.1.0"
./scripts/build_dmg.sh
```

### 証明書の指定

```bash
./scripts/build_dmg.sh \
  "Developer ID Application: YOUR NAME (TEAM_ID)" \
  "your-email@example.com"
```

### 高度なカスタマイズ

`build_dmg.sh` の先頭セクションで以下を変更可能:
- `APP_NAME`: アプリケーション名
- `BUNDLE_ID`: バンドル識別子
- `SCHEME_NAME`: Xcode スキーム
- `NOTARIZE_PROFILE`: Keychain プロフィール名

---

## 🔐 セキュリティに関する注意

### Apple ID パスワードの保護

- ⚠️ アプリ固有パスワードは git に保存しない
- ✅ Keychain に安全に保存（自動）
- ✅ 同じパスワードを複数の CI/CD ツールで使用可能

### 秘密鍵の保護

- Developer ID の秘密鍵は Keychain に保存
- macOS のセキュリティ機構で保護
- エクスポート不可（セキュリティ上の理由）

### 証明書の有効期限

- Developer ID Application: **5 年間**
- 更新予定日は Apple から通知
- 更新用の新しい証明書を同じプロセスで取得

---

## 📚 参考資料

### Apple 公式ドキュメント

- [Code Signing Guide](https://developer.apple.com/documentation/security/code_signing)
- [Notarizing macOS Software Before Distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Creating the macOS App](https://developer.apple.com/documentation/xcode/creating-the-macos-app)

### Developer ID について

- [Distribute your app outside the App Store](https://developer.apple.com/documentation/security/distributing_your_app_for_mac)

---

## 🤝 サポート

問題が発生した場合:

1. **RELEASE_GUIDE.md のトラブルシューティングを確認**
2. **Apple Developer Support に問い合わせ**
   - https://developer.apple.com/support/
3. **Apple Developer Forum で質問**
   - https://forums.developer.apple.com/

---

## 📄 ライセンス

このスクリプトは AI Mac Optimizer プロジェクトの一部です。

---

**最終更新:** 2026 年 3 月 14 日
**バージョン:** 2.0.0
