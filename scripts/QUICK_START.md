# 🚀 クイックスタート - DMG ビルド

AI Mac Optimizer を最短で DMG にビルド・署名・公証する手順です。

---

## 初回セットアップ（1 回だけ実行）

### 1️⃣ Developer ID Application 証明書を取得

```
https://developer.apple.com/account/resources/certificates/list にアクセス
   ↓
「+」をクリック → 「Developer ID Application」を選択
   ↓
Keychain Access で CSR を生成してアップロード
   ↓
ダウンロードした .cer ファイルをダブルクリック
```

**確認:**
```bash
security find-identity -p codesigning -v | grep "Developer ID"
```

### 2️⃣ Notarytool 認証情報を設定

```bash
xcrun notarytool store-credentials "AIMacOptimizer" \
  --apple-id your-email@example.com \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password"
```

**パスワード生成:** https://appleid.apple.com → Sign-In and Security → App-Specific Passwords

**Team ID 確認:**
```bash
security find-identity -p codesigning -v | grep "Developer ID"
# 括弧内の 10 文字が Team ID
```

---

## 毎回の実行

### 🔨 ビルド・署名・公証を実行

```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer
./scripts/build_dmg.sh
```

**自動処理:**
- ✅ System 要件の確認
- ✅ Release ビルド
- ✅ Developer ID で署名（ハードニング化されたランタイム有効）
- ✅ DMG ディスクイメージ作成
- ✅ DMG に署名
- ✅ Apple Notary Service で公証
- ✅ 公証チケットをステープル

### ✅ 完成物の確認

```bash
# アプリケーション
/Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer.app

# 配布用 DMG
/Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer-latest.dmg
```

---

## 署名・公証の検証

```bash
# アプリケーション署名を確認
codesign --display --verbose \
  /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer.app

# DMG が公証されているか確認
xcrun stapler validate \
  /Users/kurosuken/Desktop/AIMacOptimizer/build/release/AIMacOptimizer-latest.dmg
```

期待される出力:
```
valid on disk
The staple on this file is valid on this system.
```

---

## トラブルシューティング

| エラー | 解決方法 |
|--------|--------|
| xcodebuild not found | `xcode-select --install` |
| 証明書が見つからない | https://developer.apple.com で証明書を取得し、ダブルクリック |
| Keychain 認証情報が見つからない | `xcrun notarytool store-credentials ...` を実行 |
| Code signing failed | `security unlock-keychain` でキーチェーンをロック解除 |

---

## 詳細ガイド

完全な手順は **RELEASE_GUIDE.md** を参照してください。

```bash
open /Users/kurosuken/Desktop/AIMacOptimizer/scripts/RELEASE_GUIDE.md
```

---

**最速実行:**
```bash
cd /Users/kurosuken/Desktop/AIMacOptimizer && ./scripts/build_dmg.sh
```

🎉 Done!
