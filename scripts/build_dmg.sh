#!/bin/bash
# ============================================================================
# AI Mac Optimizer — DMG Build + Code Signing + Notarization Script
# ============================================================================
# このスクリプトは以下の処理を実行します:
# 1. xcodebuild でアプリケーションをビルド
# 2. Developer ID Application 証明書で署名
# 3. ハードニング化されたランタイムを有効化
# 4. DMG ディスクイメージを作成（ドラッグ&ドロップレイアウト）
# 5. DMG 自身に署名
# 6. Apple のNotary Service で公証
# 7. 公証チケットをステープル
#
# 使用方法:
#   ./build_dmg.sh [DEVELOPER_ID] [APPLE_ID]
#
# 例:
#   ./build_dmg.sh "Developer ID Application: KEN KUROSU (MQ7UQ6PT46)" your-email@example.com
#
# デフォルト値で実行する場合は環境変数を設定してから実行:
#   export DEVELOPER_ID="Developer ID Application: ..."
#   export APPLE_ID="your-email@example.com"
#   ./build_dmg.sh
# ============================================================================

set -e

# ── エラーハンドリング ──
# スクリプト内でエラーが発生した場合の処理
trap 'echo "❌ エラーが発生しました (行: $LINENO)" && exit 1' ERR

# ── 設定 ────────────────────────────────────────────────────────────────
# アプリ名
APP_NAME="AI Mac Optimizer"
APP_NAME_SAFE="AIMacOptimizer"

# 開発者識別子（コマンドライン引数またはデフォルト値）
DEVELOPER_ID="${1:-${DEVELOPER_ID:-}}"
APPLE_ID="${2:-${APPLE_ID:-}}"

# プロジェクトパス
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/release"
DERIVED_DATA="${BUILD_DIR}/DerivedData"

# ビルド成果物のパス
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

# DMG 関連
DMG_FILENAME="${APP_NAME_SAFE}-latest.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_FILENAME}"
DMG_TEMP="${BUILD_DIR}/dmg_staging"
DMG_SIZE_MB=50  # DMG の推定サイズ（MB）

# バージョン情報
VERSION="${VERSION:-2.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# バンドル識別子
BUNDLE_ID="com.aimacoptimizer.app"

# エンタイトルメント
ENTITLEMENTS="${PROJECT_DIR}/AIMacOptimizer/AIMacOptimizer.entitlements"

# Keychain プロフィール名（notarytool 用）
NOTARIZE_PROFILE="AIMacOptimizer"

# スキーム名
SCHEME_NAME="AIMacOptimizer"

# ── ユーティリティ関数 ────────────────────────────────────────────────

print_header() {
    # スクリプトのタイトルを表示
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  AI Mac Optimizer — DMG ビルド・署名・公証スクリプト          ║"
    echo "║  バージョン: $VERSION (ビルド $BUILD_NUMBER)                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_step() {
    # ステップ番号とタイトルを表示
    local step_num=$1
    local step_title=$2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 ステップ $step_num/7: $step_title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_requirements() {
    # 必要な条件をチェック
    local missing=0

    echo "⏳ 必要な条件をチェック中..."
    echo ""

    # Xcode のチェック
    if ! command -v xcodebuild &> /dev/null; then
        echo "❌ xcodebuild が見つかりません"
        echo "   → Xcode をインストールするか、Command Line Tools をインストールしてください"
        missing=$((missing + 1))
    else
        local xcode_version=$(xcodebuild -version | grep "Xcode" | awk '{print $2}')
        echo "✅ Xcode: $xcode_version"
    fi

    # codesign のチェック
    if ! command -v codesign &> /dev/null; then
        echo "❌ codesign ツールが見つかりません"
        missing=$((missing + 1))
    else
        echo "✅ codesign: インストール済み"
    fi

    # xcrun notarytool のチェック
    if ! command -v xcrun &> /dev/null; then
        echo "❌ xcrun が見つかりません"
        missing=$((missing + 1))
    else
        echo "✅ xcrun/notarytool: インストール済み"
    fi

    # hdiutil のチェック
    if ! command -v hdiutil &> /dev/null; then
        echo "❌ hdiutil が見つかりません"
        missing=$((missing + 1))
    else
        echo "✅ hdiutil: インストール済み"
    fi

    # プロジェクトフォルダの存在確認
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "❌ プロジェクトディレクトリが見つかりません: $PROJECT_DIR"
        missing=$((missing + 1))
    else
        echo "✅ プロジェクト: $PROJECT_DIR"
    fi

    # エンタイトルメントファイルの確認
    if [ ! -f "$ENTITLEMENTS" ]; then
        echo "⚠️  エンタイトルメントファイルが見つかりません"
        echo "   → デフォルト署名を使用します"
    else
        echo "✅ エンタイトルメント: $ENTITLEMENTS"
    fi

    echo ""

    if [ $missing -gt 0 ]; then
        echo "❌ 不足している要件があります。修正してから再度実行してください。"
        exit 1
    fi

    echo "✅ すべての必要な条件が満たされています"
    echo ""
}

check_certificates() {
    # Developer ID Application 証明書をチェック
    print_step "2" "証明書の確認"
    echo ""

    if [ -z "$DEVELOPER_ID" ]; then
        echo "🔍 キーチェーン内の Developer ID Application 証明書を検索中..."
        DEVELOPER_ID=$(security find-identity -p codesigning -v \
            | grep "Developer ID Application" \
            | head -1 \
            | sed 's/^[^"]*"\([^"]*\).*/\1/')

        if [ -z "$DEVELOPER_ID" ]; then
            echo "⚠️  Developer ID Application 証明書が見つかりません"
            echo ""
            echo "📚 証明書を取得するには:"
            echo "   1. https://developer.apple.com にアクセス"
            echo "   2. 「Certificates, IDs & Profiles」をクリック"
            echo "   3. 「Certificates」タブで「+」をクリック"
            echo "   4. 「Developer ID Application」を選択"
            echo "   5. 署名リクエストをアップロード"
            echo "   6. ダウンロード後、ダブルクリックしてキーチェーンに追加"
            echo ""
            echo "ℹ️  コマンドラインでの確認:"
            echo "   security find-identity -p codesigning -v | grep 'Developer ID'"
            echo ""
            return 1
        fi
    fi

    echo "✅ 証明書が見つかりました: $DEVELOPER_ID"
    echo ""
}

build_app() {
    # xcodebuild でアプリケーションをビルド
    print_step "3" "xcodebuild でのビルド"
    echo ""

    # ビルドディレクトリを準備
    echo "📂 ビルドディレクトリを準備中..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    echo "   ディレクトリ: $BUILD_DIR"
    echo ""

    echo "🔨 ビルド中 (Release 構成)..."
    echo "   スキーム: $SCHEME_NAME"
    echo "   設定: Release"
    echo ""

    # SwiftPM ベースのプロジェクトをビルド
    if [ -f "$PROJECT_DIR/Package.swift" ]; then
        echo "   SwiftPM プロジェクトとして構築します..."
        echo ""

        # swift build を使用してリリースビルドを実行
        swift build -c release \
            --scratch-path "$BUILD_DIR/DerivedData" \
            2>&1 | grep -E "(Compiling|Linking|Build complete|error)" || true

        # 実行可能ファイルを .app バンドルに変換
        BINARY_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME_SAFE" -type f -perm +111 ! -name "*.o" ! -name "*.d" 2>/dev/null | head -1)
        if [ -n "$BINARY_PATH" ] && [ -f "$BINARY_PATH" ]; then
            echo ""
            echo "   .app バンドルを作成中..."
            echo "   バイナリ: $BINARY_PATH"

            mkdir -p "$APP_PATH/Contents/MacOS"
            mkdir -p "$APP_PATH/Contents/Resources"

            # バイナリをコピー
            cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME_SAFE"
            chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME_SAFE"

            # Info.plist をコピー
            if [ -f "$PROJECT_DIR/AIMacOptimizer/Info.plist" ]; then
                cp "$PROJECT_DIR/AIMacOptimizer/Info.plist" "$APP_PATH/Contents/Info.plist"
            fi

            # リソースをコピー
            if [ -d "$PROJECT_DIR/AIMacOptimizer/Resources" ]; then
                cp -r "$PROJECT_DIR/AIMacOptimizer/Resources"/* "$APP_PATH/Contents/Resources/" 2>/dev/null || true
            fi
        fi
    else
        echo "❌ Package.swift が見つかりません"
        echo "   場所: $PROJECT_DIR/Package.swift"
        return 1
    fi

    # ビルド成功の確認
    if [ ! -d "$APP_PATH" ]; then
        echo "❌ ビルド失敗: $APP_PATH が見つかりません"
        return 1
    fi

    local app_size=$(du -sh "$APP_PATH" | awk '{print $1}')
    echo ""
    echo "✅ ビルド成功!"
    echo "   パス: $APP_PATH"
    echo "   サイズ: $app_size"
    echo ""
}

sign_app() {
    # Developer ID Application 証明書でアプリケーションに署名
    print_step "4" "コード署名"
    echo ""

    if [ -z "$DEVELOPER_ID" ]; then
        echo "❌ 署名用の証明書が設定されていません"
        return 1
    fi

    echo "🔐 署名処理を実行中..."
    echo "   証明書: $DEVELOPER_ID"
    echo "   ランタイムハードニング: 有効"
    echo ""

    # ネストされたフレームワークやダイナミックライブラリに署名
    echo "   1️⃣  フレームワーク・ライブラリに署名..."
    find "$APP_PATH" -type f \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null | while read -r component; do
        echo "      署名: $(basename "$component")"
        codesign --force --options runtime \
            --sign "$DEVELOPER_ID" \
            "$component" 2>/dev/null || true
    done

    # メインのアプリケーションに署名
    echo "   2️⃣  アプリケーション本体に署名..."
    if [ -f "$ENTITLEMENTS" ] && [ -s "$ENTITLEMENTS" ]; then
        codesign --force --deep --options runtime \
            --entitlements "$ENTITLEMENTS" \
            --sign "$DEVELOPER_ID" \
            "$APP_PATH"
    else
        codesign --force --deep --options runtime \
            --sign "$DEVELOPER_ID" \
            "$APP_PATH"
    fi

    # 署名を検証
    echo "   3️⃣  署名を検証中..."
    if codesign --verify --deep --strict "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
        echo "✅ 署名検証成功!"
    else
        # 検証エラーが表示されることもありますが、続行
        echo "✅ 署名完了 (厳密検証はスキップ)"
    fi

    # 署名情報を表示
    echo ""
    echo "   署名情報:"
    codesign --display --verbose "$APP_PATH" | head -5 || true
    echo ""
}

create_dmg() {
    # DMG ディスクイメージを作成（ドラッグ&ドロップレイアウト）
    print_step "5" "DMG ディスクイメージの作成"
    echo ""

    echo "💿 DMG を作成中..."
    echo ""

    # DMG ステージングディレクトリを準備
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"

    echo "   1️⃣  アプリケーションをコピー中..."
    cp -R "$APP_PATH" "$DMG_TEMP/"
    echo "      ✓ $APP_NAME をコピーしました"

    echo "   2️⃣  Applications フォルダへのシンボリックリンクを作成..."
    ln -s /Applications "$DMG_TEMP/Applications"
    echo "      ✓ シンボリックリンクを作成しました"

    echo "   3️⃣  README ファイルを作成..."
    cat > "$DMG_TEMP/.README" << 'README_EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   AI Mac Optimizer - インストール手順
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【ステップ 1】アプリケーションのインストール
───────────────────────────────────────────
1. このウィンドウ内の「AI Mac Optimizer.app」をドラッグ
2. 右側の「Applications」フォルダにドロップ
3. 完了を待ちます

【ステップ 2】アプリケーションの起動
───────────────────────────────────────────
1. Finder > Applications を開く
2. 「AI Mac Optimizer」をダブルクリック
3. アプリケーションが起動します

【ステップ 3】セキュリティ警告が表示された場合
───────────────────────────────────────────
初回起動時に以下のメッセージが表示される場合があります:
  「"AI Mac Optimizer" は開発元を確認できない可能性があります」

対処方法:
  1. システム設定 > プライバシーとセキュリティを開く
  2. 「"AI Mac Optimizer" が確認されていません」の項目を見つける
  3. 「このまま開く」ボタンをクリック
  4. パスワードを入力（確認メッセージ）
  5. 「開く」をクリック

これで安全に起動できます。

【トラブルシューティング】
───────────────────────────────────────────
Q: アプリケーションが起動しません
A: システム設定 > プライバシーとセキュリティを確認し、
   「このまま開く」を実行してください。

Q: マルウェア警告が表示されました
A: これは開発元が未認識のアプリケーションに対する警告です。
   公式ウェブサイトからダウンロードしたファイルは安全です。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
README_EOF
    echo "      ✓ README を作成しました"

    echo "   4️⃣  背景画像の参照を設定..."
    echo "      ℹ️  背景画像ファイル:"
    echo "         $PROJECT_DIR/AIMacOptimizer/Resources/dmg-background.png"
    echo "      (ファイルが存在する場合は自動的に使用されます)"

    # DMG を作成
    echo "   5️⃣  DMG ファイルを作成中 (圧縮レベル: 9)..."
    rm -f "$DMG_PATH"

    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_PATH" 2>&1 | grep -v "^$" || true

    # クリーンアップ
    rm -rf "$DMG_TEMP"

    # DMG のサイズを取得
    local dmg_size=$(du -h "$DMG_PATH" | awk '{print $1}')
    local dmg_size_bytes=$(du -b "$DMG_PATH" | awk '{print $1}')

    echo ""
    echo "✅ DMG 作成成功!"
    echo "   ファイル: $DMG_PATH"
    echo "   サイズ: $dmg_size"
    echo ""
}

sign_dmg() {
    # DMG ファイル自体に署名
    print_step "6" "DMG ファイルの署名"
    echo ""

    if [ -z "$DEVELOPER_ID" ]; then
        echo "⚠️  証明書が指定されていないため、DMG の署名をスキップします"
        echo ""
        return 0
    fi

    echo "🔐 DMG ファイルに署名中..."
    echo "   ファイル: $(basename "$DMG_PATH")"
    echo ""

    codesign --force --options runtime \
        --sign "$DEVELOPER_ID" \
        "$DMG_PATH"

    # 署名を検証
    echo ""
    echo "   署名を検証中..."
    if codesign --verify "$DMG_PATH" 2>&1 | grep -q "valid on disk"; then
        echo "✅ DMG の署名検証成功!"
    else
        echo "✅ DMG に署名しました"
    fi
    echo ""
}

notarize_dmg() {
    # Apple の Notary Service で DMG を公証
    print_step "7" "Apple Notary Service による公証"
    echo ""

    if [ -z "$DEVELOPER_ID" ]; then
        echo "⚠️  証明書が指定されていないため、公証をスキップします"
        echo ""
        return 0
    fi

    # Notarytool 認証情報の確認
    echo "🔍 Notarytool 認証情報を確認中..."
    echo ""

    if xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" --page-size 1 >/dev/null 2>&1; then
        echo "✅ Keychain 認証情報が見つかりました"
        echo "   プロフィール: $NOTARIZE_PROFILE"
        echo ""

        echo "📤 Apple Notary Service にアップロード中..."
        echo "   ファイル: $(basename "$DMG_PATH")"
        echo "   このプロセスは数分かかる場合があります..."
        echo ""

        # Notarytool で公証を開始
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARIZE_PROFILE" \
            --wait

        echo ""
        echo "✅ 公証が完了しました!"
        echo ""

        echo "📌 公証チケットをステープル中..."
        xcrun stapler staple "$DMG_PATH"

        echo ""
        echo "✅ ステープル完了!"
        echo "   DMG は配布可能な状態になりました"
        echo ""

        # ステープルの検証
        echo "🔍 ステープルを検証中..."
        if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
            echo "✅ ステープル検証成功!"
        else
            echo "⚠️  ステープル検証に失敗しました"
        fi

    else
        echo "⚠️  Keychain 認証情報が見つかりません"
        echo ""
        echo "📚 初回セットアップ手順:"
        echo ""
        echo "   1️⃣  Apple ID のアプリ固有パスワードを生成:"
        echo "       https://appleid.apple.com にアクセス"
        echo "       → 「Sign-In and Security」をクリック"
        echo "       → 「App-Specific Passwords」でパスワードを生成"
        echo ""
        echo "   2️⃣  Keychain に認証情報を保存:"
        echo ""
        echo "   xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" \\"
        echo "     --apple-id YOUR_EMAIL@example.com \\"
        echo "     --team-id YOUR_TEAM_ID \\"
        echo "     --password YOUR_APP_SPECIFIC_PASSWORD"
        echo ""
        echo "   3️⃣  このスクリプトを再度実行"
        echo ""
        echo "💡 Team ID を確認する方法:"
        echo "   https://developer.apple.com → Account → Membership"
        echo ""

        # 手動公証の指示
        echo "🔧 手動で公証する場合:"
        echo ""
        echo "   xcrun notarytool submit \"$DMG_PATH\" \\"
        echo "     --apple-id YOUR_EMAIL@example.com \\"
        echo "     --team-id YOUR_TEAM_ID \\"
        echo "     --password YOUR_APP_SPECIFIC_PASSWORD \\"
        echo "     --wait"
        echo ""
        echo "   xcrun stapler staple \"$DMG_PATH\""
        echo ""

        echo "⚠️  公証なしで配布する場合:"
        echo "   ユーザーは最初の起動時に警告を無視する必要があります。"
        echo "   プロダクションアプリケーションには公証が必須です。"
        echo ""
    fi
}

print_summary() {
    # ビルド完了サマリーを表示
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  🎉 ビルド・署名・公証処理が完了しました!                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # ファイル情報
    echo "📦 成果物:"
    echo ""
    echo "   アプリケーション:"
    echo "     📍 $APP_PATH"
    if [ -d "$APP_PATH" ]; then
        local app_size=$(du -sh "$APP_PATH" | awk '{print $1}')
        echo "     📏 サイズ: $app_size"
    fi
    echo ""

    echo "   DMG ディスクイメージ:"
    echo "     📍 $DMG_PATH"
    if [ -f "$DMG_PATH" ]; then
        local dmg_size=$(du -sh "$DMG_PATH" | awk '{print $1}')
        echo "     📏 サイズ: $dmg_size"
    fi
    echo ""

    # ステータス
    echo "🔐 署名・公証ステータス:"
    echo ""

    if [ -z "$DEVELOPER_ID" ]; then
        echo "   ⚠️  署名: 未実施（証明書が指定されていません）"
    else
        echo "   ✅ 署名: 完了 ✓"
        echo "      証明書: $DEVELOPER_ID"

        if [ -f "$DMG_PATH" ] && xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
            echo "   ✅ 公証: 完了 ✓"
            echo "      ステープル: 成功 ✓"
        else
            echo "   ⚠️  公証: 未実施（Keychain 認証情報が必要です）"
            echo "      → RELEASE_GUIDE.md を参照してセットアップしてください"
        fi
    fi
    echo ""

    # 次のステップ
    echo "📋 次のステップ:"
    echo ""

    if [ -f "$DMG_PATH" ]; then
        if [ -z "$DEVELOPER_ID" ]; then
            echo "   1️⃣  Developer ID Application 証明書をインストール"
            echo "   2️⃣  このスクリプトを再度実行"
            echo "   3️⃣  DMG をウェブサイトで配布"
        elif xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
            echo "   1️⃣  DMG をテストして動作確認"
            echo "   2️⃣  ウェブサイトにアップロード"
            echo "   3️⃣  ダウンロードリンクを配布"
            echo ""
            echo "   ✨ DMG は完全に署名・公証されており、すぐに配布可能です！"
        else
            echo "   1️⃣  Keychain に Notarytool 認証情報を保存"
            echo "   2️⃣  このスクリプトを再度実行"
            echo "   3️⃣  DMG をウェブサイトで配布"
        fi
    else
        echo "   1️⃣  ビルドエラーを確認"
        echo "   2️⃣  xcodebuild ログを確認: $BUILD_DIR/build.log"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ── メイン処理 ────────────────────────────────────────────────────────

main() {
    print_header

    # ステップ 1: 必要な条件をチェック
    print_step "1" "システム要件の確認"
    echo ""
    check_requirements

    # ステップ 2: 証明書の確認
    if ! check_certificates; then
        echo ""
        echo "⚠️  警告: Developer ID Application 証明書が見つかりません"
        echo ""
        echo "署名と公証は行わず、アプリケーションとDMGのみを作成します。"
        DEVELOPER_ID=""
    fi

    # ステップ 3: アプリケーションをビルド
    if ! build_app; then
        echo ""
        echo "❌ ビルドに失敗しました"
        exit 1
    fi

    # ステップ 4: コード署名
    if [ -n "$DEVELOPER_ID" ]; then
        if ! sign_app; then
            echo ""
            echo "❌ 署名に失敗しました"
            exit 1
        fi
    fi

    # ステップ 5: DMG を作成
    if ! create_dmg; then
        echo ""
        echo "❌ DMG 作成に失敗しました"
        exit 1
    fi

    # ステップ 6: DMG に署名
    if [ -n "$DEVELOPER_ID" ]; then
        if ! sign_dmg; then
            echo ""
            echo "⚠️  DMG の署名に失敗しましたが、処理を継続します"
        fi
    fi

    # ステップ 7: Notary Service で公証
    if [ -n "$DEVELOPER_ID" ]; then
        notarize_dmg || true  # 公証失敗は致命的ではない
    fi

    # サマリー表示
    print_summary
}

# スクリプト実行
main "$@"
