<p align="center">
  <img src="https://raw.githubusercontent.com/sephar-im/Sippur/refs/heads/main/logo_sepharim.png" alt="Cabecera" width="800">
</p>

# Sepharim Sippur

> Coded with Codex.

Sepharim Sippur is a native macOS app for ultra-fast voice-to-text note capture.

Click the circle or use a shortcut, speak, stop, and get a local text note saved automatically.

## What It Does

- Native macOS app built with Swift and SwiftUI
- Minimal floating capture control
- Optional global shortcut for start/stop capture
- Local microphone recording
- Local transcription with Whisper
- Automatic note export to a user-selected folder
- Output as `TXT` or `MD`
- `Normal` and `Obsidian` markdown modes
- Optional local LLM cleanup with Ollama and `qwen2.5:1.5b`
- Menu bar settings, no heavy preferences UI
- Automatic UI language based on the system language

## How It Works

1. Start capture by clicking the circle or using your configured shortcut.
2. Speak.
3. Stop capture.
4. The app transcribes the recording locally with Whisper.
5. The note is saved automatically in your chosen folder.

The product keeps notes, not recordings. Audio is only used temporarily during capture and is removed after transcription.

## Output Modes

### TXT

Saves clean plain text only.

### Markdown

Saves a simple markdown note with:

- title
- date
- body

### Obsidian Mode

Still saves plain markdown files. It does not require plugins, APIs, or templates.

The difference is intentionally small:

- `Normal` mode writes simple markdown with a title, a date line, and the body
- `Obsidian` mode writes markdown that fits naturally in a vault, including a small `created` frontmatter field

## Optional Local LLM Cleanup

Local LLM cleanup is optional and the app remains fully useful without it.

If enabled, the app uses:

- Ollama
- `qwen2.5:1.5b`

This stage is not for chat. It is only used after Whisper transcription to:

- improve punctuation
- improve paragraphing
- correct obvious transcription mistakes when the context is clear
- keep the final wording when the speaker clearly self-corrects
- optionally produce a cleaner markdown title

It is meant to help, not to be perfect. Important notes should still be reviewed.

## First Launch

On first launch, the app prepares runtime dependencies instead of bundling large model files into the installer.

- Whisper assets are downloaded only when needed
- Ollama is only checked and used when local LLM cleanup is enabled
- Optional LLM model download is separate from the core Whisper flow

This keeps distribution smaller and the installation flow simpler.

## Requirements

- macOS 14 or later
- Xcode command line tools or Xcode
- Microphone permission for capture

Optional for local LLM cleanup:

- [Ollama](https://ollama.com)

## Run From Source

```bash
cd /Users/om/Documents/SSSS/sepharim_sippur
swift run
```

Run tests:

```bash
cd /Users/om/Documents/SSSS/sepharim_sippur
swift test
```

## Build Distribution Artifacts

Build the app bundle:

```bash
./scripts/build_app_bundle.sh
```

Default output:

- `dist/0.1.0/Sepharim Sippur.app`

Build the DMG:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION="1.0.0" \
./scripts/build_dmg.sh
```

Default output:

- `dist/1.0.0/SepharimSippur-1.0.0.dmg`

Notarize the release:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION="1.0.0" \
NOTARYTOOL_PROFILE="sepharim-sippur-notary" \
./scripts/notarize_release.sh
```

More detail is available in [docs/distribution.md](/Users/om/Documents/SSSS/sepharim_sippur/docs/distribution.md).

## Project Structure

- [Sources/SepharimSippur](/Users/om/Documents/SSSS/sepharim_sippur/Sources/SepharimSippur): app logic, UI, recording, transcription, export, optional LLM cleanup
- [Sources/SepharimSippurApp](/Users/om/Documents/SSSS/sepharim_sippur/Sources/SepharimSippurApp): executable entry point
- [Tests/SepharimSippurTests](/Users/om/Documents/SSSS/sepharim_sippur/Tests/SepharimSippurTests): automated tests
- [scripts](/Users/om/Documents/SSSS/sepharim_sippur/scripts): build, packaging, and notarization scripts

## Status

Sepharim Sippur is built around a narrow MVP philosophy:

- fast capture
- local transcription
- automatic saving
- minimal UI
- small, understandable code

That constraint is deliberate.
