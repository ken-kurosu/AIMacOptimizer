#!/bin/bash
# Generate .icns from SVG for macOS app icon
# Requires: brew install librsvg (for rsvg-convert) or use sips

set -e

SVG_PATH="AIMacOptimizer/Resources/AppIcon.svg"
ICONSET_DIR="AIMacOptimizer/Resources/AppIcon.iconset"
ICNS_PATH="AIMacOptimizer/Resources/AppIcon.icns"

echo "🎨 Generating app icon from SVG..."

mkdir -p "$ICONSET_DIR"

# Required icon sizes for macOS
SIZES=(16 32 64 128 256 512 1024)

for size in "${SIZES[@]}"; do
    echo "  Generating ${size}x${size}..."

    # 1x
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w "$size" -h "$size" "$SVG_PATH" > "$ICONSET_DIR/icon_${size}x${size}.png"
    else
        # Fallback: use sips with a pre-rendered 1024 PNG
        echo "  ⚠️  rsvg-convert not found. Install with: brew install librsvg"
        echo "  Trying sips fallback..."
        break
    fi

    # 2x (Retina)
    double=$((size * 2))
    if [ "$double" -le 1024 ]; then
        if command -v rsvg-convert &> /dev/null; then
            rsvg-convert -w "$double" -h "$double" "$SVG_PATH" > "$ICONSET_DIR/icon_${size}x${size}@2x.png"
        fi
    fi
done

# Generate .icns
echo "  Converting to .icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH" 2>/dev/null || {
    echo "  ⚠️  iconutil failed. You can manually convert using an online tool."
    echo "  SVG is at: $SVG_PATH"
}

# Cleanup
rm -rf "$ICONSET_DIR"

echo "✅ Icon generated at: $ICNS_PATH"
