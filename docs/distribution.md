# Sepharim Sippur Distribution

Sepharim Sippur ships as a signed `.app` inside a signed `.dmg`.

This keeps installation standard for macOS users:
- Open the DMG
- Drag `Sepharim Sippur.app` to `/Applications`
- Launch the app
- Let first-launch dependency bootstrap fetch Whisper assets, and optional Ollama assets only if LLM cleanup is enabled

## Why DMG-first

DMG distribution fits this product better than PKG:
- The app is a simple drag-to-install utility, not a system component
- No privileged installer is needed
- The installer stays small because Whisper and Ollama models are not bundled into the artifact
- Runtime bootstrap is safer for large, optional assets because it keeps releases fast and lets dependency retries happen inside the app, after installation

## Release Files

- `scripts/build_app_bundle.sh`
  Builds the release executable, wraps it in `Sepharim Sippur.app`, generates `AppIcon.icns` from `sippur.png`, writes `Info.plist`, and signs the app.

- `scripts/build_dmg.sh`
  Creates a DMG containing the `.app` plus an `/Applications` symlink, then signs the DMG.

- `scripts/notarize_release.sh`
  Notarizes the signed app first, staples it, rebuilds the DMG from that stapled app, then notarizes and staples the DMG.

## Signing

For real distribution, use a Developer ID Application identity:

```bash
security find-identity -v -p codesigning
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Local validation without a certificate is still possible because the scripts fall back to ad-hoc signing when `SIGNING_IDENTITY` is not set.

## Build the App Bundle

```bash
cd /Users/om/Documents/SSSS/sepharim_sippur
./scripts/build_app_bundle.sh
```

Output:
- `dist/Sepharim Sippur.app`

## Build the DMG

```bash
cd /Users/om/Documents/SSSS/sepharim_sippur
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION="1.0.0" \
./scripts/build_dmg.sh
```

Output:
- `dist/SepharimSippur-1.0.0.dmg`

## Notarization

Preferred setup is a stored `notarytool` keychain profile:

```bash
xcrun notarytool store-credentials "sepharim-sippur-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then notarize the release:

```bash
cd /Users/om/Documents/SSSS/sepharim_sippur
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION="1.0.0" \
NOTARYTOOL_PROFILE="sepharim-sippur-notary" \
./scripts/notarize_release.sh
```

The notarization script will:
1. Build and sign the `.app`
2. Zip and submit the app for notarization
3. Staple the app
4. Build and sign the DMG from the stapled app
5. Submit the DMG for notarization
6. Staple the DMG
7. Run Gatekeeper checks on the final artifacts

## Release Checklist

- Confirm `BUNDLE_ID`, `VERSION`, and `BUILD_NUMBER`
- Confirm `sippur.png` is the final shipping icon
- Build the signed `.app`
- Build the signed `.dmg`
- Notarize and staple both the app and DMG
- Mount the DMG and verify it contains:
  - `Sepharim Sippur.app`
  - `Applications` shortcut
- Drag the app to `/Applications`
- Launch from `/Applications`
- Confirm microphone permission prompt appears correctly
- Confirm first-launch Whisper bootstrap works after distribution
- Confirm optional Ollama bootstrap only runs when LLM cleanup is enabled
