#!/bin/bash
# AI Mac Optimizer — SwiftPM 用 リリースビルド（署名・公証・DMG化）
# 前提:
#   - Developer ID Application 証明書がキーチェーンにある
#   - notarytool プロファイル（既定名 "AIMacOptimizer"）が設定済み
#       xcrun notarytool store-credentials "AIMacOptimizer" --apple-id <id> --team-id <team> --password <app専用pw>
# 使い方: ./scripts/build_dmg.sh
set -euo pipefail

APP_NAME="AI Mac Optimizer"
BUNDLE_ID="com.aimacoptimizer.app"
TEAM_ID="AUJDN6C7VB"
SIGN_ID="Developer ID Application: KEN KUROSU (${TEAM_ID})"
NOTARY_PROFILE="AIMacOptimizer"

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJ/AIMacOptimizer"
# バージョン/ビルド番号は Info.plist を唯一の真実として読む（自動更新の比較基準）
VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$SRC/Info.plist")"
ENTITLEMENTS="$SRC/AIMacOptimizer.entitlements"
OUT="$PROJ/build/release"
APP="$OUT/${APP_NAME}.app"
STAGING="$OUT/dmg_staging"
DMG="$OUT/AIMacOptimizer-v${VERSION}.dmg"

echo "▶ 1/7 ビルド (swift build -c release)"
swift build -c release --package-path "$PROJ" >/dev/null
EXE="$PROJ/.build/release/AIMacOptimizer"
[ -f "$EXE" ] || { echo "❌ 実行ファイルが見つかりません: $EXE"; exit 1; }

echo "▶ 2/7 .app バンドル組み立て"
rm -rf "$APP" "$STAGING"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/AIMacOptimizer"
sed -e "s/\$(EXECUTABLE_NAME)/AIMacOptimizer/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
    -e "s/\$(PRODUCT_NAME)/${APP_NAME}/g" \
    "$SRC/Info.plist" > "$APP/Contents/Info.plist"
# アイコン (あれば)
[ -f "$SRC/Resources/AppIcon.icns" ] && cp "$SRC/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▶ 3/7 署名 (Developer ID + hardened runtime)"
codesign --force --options runtime --timestamp \
    --sign "$SIGN_ID" \
    --entitlements "$ENTITLEMENTS" \
    "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▶ 4/7 DMG 作成"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "▶ 5/7 公証 (notarytool submit --wait, 数分かかります)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ 6/7 ステープル"
xcrun stapler staple "$DMG"

echo "▶ 7/7 検証"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true
echo "▶ 8/8 自動更新マニフェスト (latest.json) 生成"
cat > "$OUT/latest.json" <<EOF
{"build": ${BUILD}, "version": "${VERSION}", "url": "https://github.com/ken-kurosu/AIMacOptimizer/releases/latest/download/AIMacOptimizer-latest.dmg", "notes": ""}
EOF
echo "   $OUT/latest.json (build ${BUILD}, v${VERSION})"

echo ""
echo "✅ 完成: $DMG"
echo "   配布: このDMGを配布すれば、Gatekeeper警告なしで起動できます。"
echo "   リリースには DMG(AIMacOptimizer-latest.dmg) と latest.json の両方をアップロードすること。"
