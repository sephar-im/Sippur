<p align="center">
  <img src="https://raw.githubusercontent.com/sephar-im/Sippur/refs/heads/main/logo_sepharim.png" alt="Cabecera" width="800">
</p>

# Sepharim Sippur

> Coded with Codex.

Sepharim Sippur is a native macOS app for ultra-fast voice-to-text note capture.

It is built around one narrow flow: record, transcribe locally, and save a text note automatically.

## Features

- Native macOS app built with Swift and SwiftUI
- Minimal floating circular capture control
- Local microphone recording
- Local Whisper transcription
- Automatic plain-text note saving
- Optional manual text cleanup with Ollama and `qwen2.5:1.5b`
- Menu bar settings
- Automatic UI language based on the system language

## Notes

- Notes are saved as plain `.txt` files with sortable timestamp filenames.
- Audio is temporary during capture and is removed after transcription.
- Local LLM cleanup is optional and only works on already saved text notes.
- This project keeps the product intentionally small and local-first.

## Requirements

- macOS 14 or later
- Microphone permission
- Optional: [Ollama](https://ollama.com) for manual text cleanup

## Project Structure

- [Sources/SepharimSippur](/Users/om/Documents/SSSS/sepharim_sippur/Sources/SepharimSippur): app logic, UI, recording, transcription, export, and optional text cleanup
- [Sources/SepharimSippurApp](/Users/om/Documents/SSSS/sepharim_sippur/Sources/SepharimSippurApp): executable entry point
- [Tests/SepharimSippurTests](/Users/om/Documents/SSSS/sepharim_sippur/Tests/SepharimSippurTests): automated tests
- [scripts](/Users/om/Documents/SSSS/sepharim_sippur/scripts): packaging and release scripts
