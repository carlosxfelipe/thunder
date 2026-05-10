#!/bin/bash
# generate_icons.sh
#
# Generates all macOS app icon sizes from icon_source.svg
# and updates the AppIcon.appiconset with the correct Contents.json.
#
# Requirements: rsvg-convert (from librsvg)
#   Install with: brew install librsvg
#
# Usage: ./assets/generate_icons.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/icon_source.svg"
OUTPUT_DIR="${SCRIPT_DIR}/../thunar/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
  echo "❌ Source icon not found: $SOURCE"
  exit 1
fi

# Check for rsvg-convert
if ! command -v rsvg-convert &>/dev/null; then
  echo "❌ rsvg-convert not found. Install with: brew install librsvg"
  exit 1
fi

echo "🔨 Generating icons from: $SOURCE"
echo "📂 Output directory: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

# macOS icon sizes (size x scale = pixel dimensions)
# size  scale  pixels  filename
ICONS=(
  "16   1x   16    icon_16x16.png"
  "16   2x   32    icon_16x16@2x.png"
  "32   1x   32    icon_32x32.png"
  "32   2x   64    icon_32x32@2x.png"
  "128  1x   128   icon_128x128.png"
  "128  2x   256   icon_128x128@2x.png"
  "256  1x   256   icon_256x256.png"
  "256  2x   512   icon_256x256@2x.png"
  "512  1x   512   icon_512x512.png"
  "512  2x   1024  icon_512x512@2x.png"
)

for entry in "${ICONS[@]}"; do
  read -r size scale pixels filename <<< "$entry"
  echo "  → ${filename} (${pixels}×${pixels}px)"
  rsvg-convert -w "$pixels" -h "$pixels" "$SOURCE" -o "${OUTPUT_DIR}/${filename}"
done

# Generate Contents.json
cat > "${OUTPUT_DIR}/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo ""
echo "✅ All icons generated successfully!"
echo "📋 Contents.json updated."
