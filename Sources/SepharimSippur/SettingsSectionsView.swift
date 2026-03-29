import SwiftUI

struct SettingsSectionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    let setGlobalShortcut: (GlobalShortcutMonitor.Shortcut?) -> Void
    let showsFirstUseHelp: Bool
    let showsModeExplanation: Bool
    let showsAdvancedLLMControls: Bool

    private var llmEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isLLMPostProcessingEnabled },
            set: { model.setLLMPostProcessingEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsFirstUseHelp, !settings.hasSeenFirstUseHelp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("First time here?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Text("Click the circle to start and stop. The note is transcribed locally and saved as text in the selected folder.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Got It") {
                        settings.markFirstUseHelpSeen()
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            section("Capture") {
                Picker("Size", selection: $settings.captureControlSize) {
                    ForEach(CaptureControlSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            section("Notes") {
                HStack(spacing: 8) {
                    Button("Choose folder") {
                        settings.chooseOutputFolder()
                    }

                    Button("Open folder") {
                        settings.openOutputFolder()
                    }
                }

                if model.lastSavedNoteURL != nil {
                    Button("Reveal last saved note") {
                        model.revealLastSavedNote()
                    }
                }

                Text(settings.outputFolderPath)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Picker("Format", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Mode", selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if showsModeExplanation {
                    Text(modeExplanationText)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Copy saved text to clipboard", isOn: $settings.copySavedNoteToClipboard)
                    .toggleStyle(.switch)
            }

            section("Shortcut") {
                HStack(alignment: .top, spacing: 8) {
                    ShortcutRecorderView(
                        shortcutDisplayName: settings.globalShortcutDisplayName,
                        onShortcutChange: setGlobalShortcut
                    )

                    if settings.globalShortcut != nil {
                        Button("Clear") {
                            setGlobalShortcut(nil)
                        }
                    }
                }
            }

            section("Local LLM") {
                Button(settings.isLLMPostProcessingEnabled ? "Disable Local LLM" : "Enable Local LLM") {
                    llmEnabledBinding.wrappedValue.toggle()
                }

                if settings.isLLMPostProcessingEnabled, !settings.hasSeenLLMCleanupHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Helpful, not perfect.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))

                        Text("It is meant to clean the Whisper text: punctuation, paragraphing, obvious speech repairs, and context-based spelling fixes. Review important notes because it can still make mistakes.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Got It") {
                            settings.markLLMCleanupHelpSeen()
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Text(model.llmStatusText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsAdvancedLLMControls, settings.isLLMPostProcessingEnabled {
                    if model.isOllamaInstalled, model.preparedLLMModel != nil {
                        Text("Uses \(LocalLLMModel.cleanupModel.label) for local cleanup.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Remove downloaded model") {
                            model.removeDownloadedLLM()
                        }
                        .disabled(model.isPreparingLLM)
                    } else if model.isOllamaInstalled {
                        Text("No local model is ready yet. Enable Local LLM to prepare \(LocalLLMModel.cleanupModel.label).")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Install Ollama to use local cleanup.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var modeExplanationText: String {
        switch settings.outputMode {
        case .normal:
            return "Normal saves simple text or markdown. In markdown it writes a plain title, a date line, and the note body."
        case .obsidian:
            return "Obsidian still saves plain markdown, but adds a created frontmatter field so the note fits naturally inside a vault."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))

            content()
        }
    }
}
