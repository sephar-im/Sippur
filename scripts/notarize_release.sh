#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Sepharim Sippur}"
VERSION="${VERSION:-1.0}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/dist}"
OUTPUT_DIR="${OUTPUT_DIR:-$OUTPUT_ROOT/$VERSION}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DMG_NAME="${DMG_NAME:-SepharimSippur-${VERSION}.dmg}"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
APP_ZIP="$OUTPUT_DIR/SepharimSippur-${VERSION}.zip"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"

if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Set SIGNING_IDENTITY to a real 'Developer ID Application: …' identity before notarizing." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for notarization." >&2
  exit 1
fi

NOTARY_ARGS=()
if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
  NOTARY_ARGS+=(--keychain-profile "$NOTARYTOOL_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${TEAM_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  NOTARY_ARGS+=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD")
elif [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" ]]; then
  NOTARY_ARGS+=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID")
  if [[ -n "${ASC_ISSUER:-}" ]]; then
    NOTARY_ARGS+=(--issuer "$ASC_ISSUER")
  fi
else
  echo "Provide notarization credentials with NOTARYTOOL_PROFILE, or APPLE_ID/TEAM_ID/APP_SPECIFIC_PASSWORD, or ASC_KEY_PATH/ASC_KEY_ID[/ASC_ISSUER]." >&2
  exit 1
fi

echo "Building signed app bundle..."
REQUIRE_DEVELOPER_ID=1 SIGNING_IDENTITY="$SIGNING_IDENTITY" OUTPUT_DIR="$OUTPUT_DIR" VERSION="$VERSION" \
  "$ROOT_DIR/scripts/build_app_bundle.sh"

echo "Preparing app archive for notarization..."
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"

echo "Submitting app archive for notarization..."
xcrun notarytool submit "$APP_ZIP" --wait "${NOTARY_ARGS[@]}"

echo "Stapling app bundle..."
xcrun stapler staple "$APP_BUNDLE"

echo "Building signed DMG from stapled app..."
REQUIRE_DEVELOPER_ID=1 SIGNING_IDENTITY="$SIGNING_IDENTITY" OUTPUT_DIR="$OUTPUT_DIR" VERSION="$VERSION" SKIP_APP_BUILD=1 \
  "$ROOT_DIR/scripts/build_dmg.sh"

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" --wait "${NOTARY_ARGS[@]}"

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

echo "Final Gatekeeper assessment..."
spctl -a -t exec -vv "$APP_BUNDLE"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

echo "Notarized release ready:"
echo "$DMG_PATH"
