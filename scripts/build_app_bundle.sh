#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Sepharim Sippur}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-SepharimSippur}"
BUNDLE_ID="${BUNDLE_ID:-com.sepharimsippur.app}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"
APP_CATEGORY="${APP_CATEGORY:-public.app-category.productivity}"
ICON_SOURCE="${ICON_SOURCE:-}"
MICROPHONE_USAGE_DESCRIPTION="${MICROPHONE_USAGE_DESCRIPTION:-Sepharim Sippur needs microphone access to turn your speech into local text notes.}"
HUMAN_READABLE_COPYRIGHT="${HUMAN_READABLE_COPYRIGHT:-Copyright © 2026 Sepharim Sippur. All rights reserved.}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/dist}"
OUTPUT_DIR="${OUTPUT_DIR:-$OUTPUT_ROOT/$VERSION}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-0}"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_INFO_PLIST="$APP_CONTENTS/Info.plist"
WORK_DIR="$OUTPUT_DIR/.build-app"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
ICNS_PATH="$APP_RESOURCES/AppIcon.icns"
ICON_RASTER_SOURCE="$WORK_DIR/AppIconSource.png"

mkdir -p "$OUTPUT_DIR"

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Developer ID signing is required for this build. Set SIGNING_IDENTITY to your 'Developer ID Application: …' identity." >&2
  exit 1
fi

if [[ -n "$ICON_SOURCE" && ! -f "$ICON_SOURCE" ]]; then
  echo "Icon source not found at $ICON_SOURCE" >&2
  exit 1
fi

for tool in swift sips iconutil codesign plutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool '$tool' is not available." >&2
    exit 1
  fi
done

echo "Building release executable..."
swift build -c release --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c release --package-path "$ROOT_DIR" --show-bin-path)"
EXECUTABLE_SOURCE="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_SOURCE" ]]; then
  echo "Release executable not found at $EXECUTABLE_SOURCE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$WORK_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$ICONSET_DIR"

cp "$EXECUTABLE_SOURCE" "$APP_MACOS/$EXECUTABLE_NAME"
chmod +x "$APP_MACOS/$EXECUTABLE_NAME"

while IFS= read -r -d '' resource_bundle; do
  cp -R "$resource_bundle" "$APP_RESOURCES/"
done < <(find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -print0)

xattr -cr "$APP_BUNDLE" 2>/dev/null || true

generate_red_circle_icon() {
  local output_path="$1"
  local script_path="$WORK_DIR/generate_red_circle_icon.swift"

  cat >"$script_path" <<'EOF'
import AppKit

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
NSColor.black.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).setFill()
let inset = size.width * 0.085
NSBezierPath(
    ovalIn: NSRect(
        x: inset,
        y: inset,
        width: size.width - (inset * 2),
        height: size.height - (inset * 2)
    )
).fill()
image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to generate icon image data.")
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
EOF

  swift "$script_path" "$output_path"
}

echo "Generating app icon..."
if [[ -n "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$ICON_RASTER_SOURCE"
else
  generate_red_circle_icon "$ICON_RASTER_SOURCE"
fi

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_RASTER_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$ICON_RASTER_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

cat >"$APP_INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>$APP_CATEGORY</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_SYSTEM_VERSION</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>$HUMAN_READABLE_COPYRIGHT</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>${MICROPHONE_USAGE_DESCRIPTION:-Sepharim Sippur needs microphone access to turn your speech into local text notes.}</string>
</dict>
</plist>
EOF

plutil -lint "$APP_INFO_PLIST" >/dev/null

sign_target() {
  local target="$1"

  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$target"
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$target"
  fi
}

echo "Signing app bundle..."
sign_target "$APP_MACOS/$EXECUTABLE_NAME"
sign_target "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  spctl -a -t exec -vv "$APP_BUNDLE"
else
  echo "Built with ad-hoc signing for local validation. Set SIGNING_IDENTITY to a Developer ID Application identity for distribution."
fi

echo "App bundle ready at:"
echo "$APP_BUNDLE"
