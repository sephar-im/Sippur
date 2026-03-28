#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Sepharim Sippur}"
VERSION="${VERSION:-0.1.0}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-0}"
SKIP_APP_BUILD="${SKIP_APP_BUILD:-0}"
DMG_NAME="${DMG_NAME:-SepharimSippur-${VERSION}.dmg}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_ROOT="$OUTPUT_DIR/.dmg-root"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

mkdir -p "$OUTPUT_DIR"

if [[ "$SKIP_APP_BUILD" != "1" ]]; then
  "$ROOT_DIR/scripts/build_app_bundle.sh"
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Developer ID signing is required for this build. Set SIGNING_IDENTITY to your 'Developer ID Application: …' identity." >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "Preparing DMG staging directory..."
rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Signing DMG..."
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$DMG_PATH"
else
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
fi

codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
else
  echo "DMG was ad-hoc signed for local validation. Set SIGNING_IDENTITY to a Developer ID Application identity for distribution."
fi

echo "DMG ready at:"
echo "$DMG_PATH"
