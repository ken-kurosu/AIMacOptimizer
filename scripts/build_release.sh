#!/bin/bash
# AI Mac Optimizer - Release Build, Sign, Notarize & DMG Creator
# Usage: ./scripts/build_release.sh
#
# Prerequisites:
#   1. Apple Developer Program membership (active)
#   2. Developer ID Application certificate installed in Keychain
#   3. App-specific password stored in Keychain:
#      xcrun notarytool store-credentials "AIMacOptimizer"
#        --apple-id YOUR_APPLE_ID
#        --team-id YOUR_TEAM_ID
#        --password YOUR_APP_SPECIFIC_PASSWORD

set -e

# ── Configuration ──
APP_NAME="AI Mac Optimizer"
SCHEME_NAME="AIMacOptimizer"
BUNDLE_ID="com.aimacoptimizer.app"
VERSION="2.0.0"
BUILD_NUMBER="1"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
DMG_NAME="AIMacOptimizer-v${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
ENTITLEMENTS="$PROJECT_DIR/AIMacOptimizer/AIMacOptimizer.entitlements"
NOTARIZE_PROFILE="AIMacOptimizer"  # Keychain profile name

echo "============================================"
echo "  AI Mac Optimizer — Release Build Script"
echo "  Version: $VERSION (Build $BUILD_NUMBER)"
echo "============================================"
echo ""

# ── Step 1: Clean & Build with Xcode ──
echo "🔨 Step 1/5: Building with Xcode..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project "$PROJECT_DIR/AIMacOptimizer.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="-" \
    clean build 2>&1 | tail -5

if [ ! -d "$APP_PATH" ]; then
    # Xcode may output with different name
    FOUND_APP=$(find "$BUILD_DIR" -name "*.app" -maxdepth 1 | head -1)
    if [ -n "$FOUND_APP" ]; then
        mv "$FOUND_APP" "$APP_PATH"
    else
        echo "❌ Build failed: .app not found in $BUILD_DIR"
        exit 1
    fi
fi

echo "✅ Build succeeded: $APP_PATH"
echo ""

# ── Step 2: Code Sign with Developer ID ──
echo "🔐 Step 2/5: Code Signing..."

# Find Developer ID certificate
SIGNING_IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')

if [ -z "$SIGNING_IDENTITY" ]; then
    echo "⚠️  Developer ID Application certificate not found."
    echo "   Please install your certificate from developer.apple.com → Certificates"
    echo ""
    echo "   Quick setup:"
    echo "   1. Open Keychain Access"
    echo "   2. Go to developer.apple.com → Certificates, IDs & Profiles"
    echo "   3. Create a 'Developer ID Application' certificate"
    echo "   4. Download and double-click to install"
    echo ""
    echo "   Continuing without signing (app will show Gatekeeper warning)..."
    SIGNED=false
else
    echo "   Using: $SIGNING_IDENTITY"

    # Sign all nested components first, then the app
    find "$APP_PATH" -name "*.dylib" -o -name "*.framework" | while read component; do
        codesign --force --options runtime \
            --sign "$SIGNING_IDENTITY" \
            "$component" 2>/dev/null || true
    done

    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_PATH"

    # Verify signature
    codesign --verify --deep --strict "$APP_PATH"
    echo "✅ Code signed and verified"
    SIGNED=true
fi
echo ""

# ── Step 3: Create DMG ──
echo "💿 Step 3/5: Creating DMG..."

DMG_TEMP="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create Applications symlink (for drag-to-install)
ln -s /Applications "$DMG_TEMP/Applications"

# Create background instructions file
cat > "$DMG_TEMP/.README.txt" << 'README'
AI Mac Optimizer のインストール方法:
1. "AI Mac Optimizer.app" を "Applications" フォルダにドラッグ
2. Applications フォルダから起動
3. 「開発元を確認できません」と表示される場合:
   → システム設定 > プライバシーとセキュリティ > 「このまま開く」をクリック
README

# Create DMG
rm -f "$DMG_PATH"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "✅ DMG created: $DMG_PATH ($DMG_SIZE)"
echo ""

# ── Step 4: Notarize ──
if [ "$SIGNED" = true ]; then
    echo "📋 Step 4/5: Notarizing with Apple..."

    # Check if notarytool credentials are stored
    if xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" --page-size 1 >/dev/null 2>&1; then
        echo "   Submitting to Apple Notary Service..."
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARIZE_PROFILE" \
            --wait

        echo "   Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"

        echo "✅ Notarization complete"
    else
        echo "⚠️  Notarization credentials not found."
        echo ""
        echo "   To set up (one-time):"
        echo "   ┌──────────────────────────────────────────────────────────┐"
        echo "   │ 1. Go to appleid.apple.com → Sign-In and Security      │"
        echo "   │    → App-Specific Passwords → Generate                  │"
        echo "   │                                                          │"
        echo "   │ 2. Store credentials in Keychain:                       │"
        echo "   │    xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\"│"
        echo "   │      --apple-id YOUR_APPLE_ID                           │"
        echo "   │      --team-id YOUR_TEAM_ID                             │"
        echo "   │      --password APP_SPECIFIC_PASSWORD                   │"
        echo "   │                                                          │"
        echo "   │ 3. Then run this script again                           │"
        echo "   └──────────────────────────────────────────────────────────┘"
        echo ""
        echo "   Manual notarization:"
        echo "   xcrun notarytool submit $DMG_PATH \\"
        echo "     --apple-id YOUR_APPLE_ID \\"
        echo "     --team-id YOUR_TEAM_ID \\"
        echo "     --password APP_SPECIFIC_PASSWORD \\"
        echo "     --wait"
        echo "   xcrun stapler staple $DMG_PATH"
    fi
else
    echo "⏭️  Step 4/5: Skipping notarization (not signed)"
fi
echo ""

# ── Step 5: Summary ──
echo "============================================"
echo "  🎉 Build Complete!"
echo "============================================"
echo ""
echo "  App:     $APP_PATH"
echo "  DMG:     $DMG_PATH"
echo "  Size:    $DMG_SIZE"
echo "  Version: $VERSION ($BUILD_NUMBER)"
echo ""

if [ "$SIGNED" = true ]; then
    echo "  Status:  ✅ Signed with Developer ID"
    if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
        echo "           ✅ Notarized & Stapled"
        echo ""
        echo "  → Ready to distribute! Upload DMG to your website."
    else
        echo "           ⚠️  Not yet notarized (see instructions above)"
        echo ""
        echo "  → After notarization, upload DMG to your website."
    fi
else
    echo "  Status:  ⚠️  Unsigned (Gatekeeper will block)"
    echo ""
    echo "  → Install Developer ID certificate first."
fi
echo ""
echo "  LP download URL to configure:"
echo "  → AIMacOptimizer_LP/index.html の downloadDMG() 関数に"
echo "    DMGのホスティングURLを設定してください"
