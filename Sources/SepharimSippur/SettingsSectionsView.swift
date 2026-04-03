import SwiftUI

struct SettingsSectionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    let setGlobalShortcut: (GlobalShortcutMonitor.Shortcut?) -> Void
    let showsFirstUseHelp: Bool

    private var whisperModelBinding: Binding<WhisperModelChoice> {
        Binding(
            get: { settings.whisperModel },
            set: { model.setWhisperModel($0) }
        )
    }

    private var llmConnectionBinding: Binding<Bool> {
        Binding(
            get: { model.isLLMConnected || model.isPreparingLLM },
            set: { model.setLLMConnectionEnabled($0) }
        )
    }

    private var llmModelBinding: Binding<String> {
        Binding(
            get: { model.selectedLLMModelName ?? model.availableLLMModels.first ?? "" },
            set: { model.setSelectedLLMModel($0) }
        )
    }

    private var whisperControlsDisabled: Bool {
        model.isBootstrappingDependencies || model.phase == .recording || model.phase == .processing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsFirstUseHelp, !settings.hasSeenFirstUseHelp {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("settings.first_use.title"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Text(L10n.tr("settings.first_use.body"))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(L10n.tr("settings.got_it")) {
                        settings.markFirstUseHelpSeen()
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            section(L10n.tr("settings.section.notes")) {
                HStack(spacing: 8) {
                    Button(L10n.tr("settings.notes.choose_folder")) {
                        settings.chooseOutputFolder()
                    }

                    Button(L10n.tr("settings.notes.open_folder")) {
                        settings.openOutputFolder()
                    }
                }

                if model.lastSavedNoteURL != nil {
                    Button(L10n.tr("settings.notes.reveal_last_saved_note")) {
                        model.revealLastSavedNote()
                    }
                }

                Text(settings.outputFolderPath)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Text(L10n.tr("settings.notes.saved_as_txt"))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L10n.tr("settings.notes.copy_saved_text_to_clipboard"), isOn: $settings.copySavedNoteToClipboard)
                    .toggleStyle(.switch)
            }

            section(L10n.tr("settings.section.shortcut")) {
                HStack(alignment: .top, spacing: 8) {
                    ShortcutRecorderView(
                        shortcutDisplayName: settings.globalShortcutDisplayName,
                        onShortcutChange: setGlobalShortcut
                    )

                    if settings.globalShortcut != nil {
                        Button(L10n.tr("settings.shortcut.clear")) {
                            setGlobalShortcut(nil)
                        }
                    }
                }
            }

            section(L10n.tr("settings.section.whisper")) {
                Picker(L10n.tr("settings.whisper.model"), selection: whisperModelBinding) {
                    ForEach(WhisperModelChoice.allCases) { model in
                        Text(model.displayLabel).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .disabled(whisperControlsDisabled)

                Text(model.whisperStatusText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isSelectedWhisperModelInstalled {
                    Button(L10n.tr("settings.whisper.remove_selected_model")) {
                        model.removeSelectedWhisperModel()
                    }
                    .disabled(whisperControlsDisabled)
                } else {
                    Button(L10n.tr("settings.whisper.download_selected_model")) {
                        model.downloadSelectedWhisperModel()
                    }
                    .disabled(whisperControlsDisabled)
                }
            }

            section(L10n.tr("settings.section.llm")) {
                if !settings.hasSeenLLMCleanupHelp {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("settings.llm.help_title"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))

                        Text(L10n.tr("settings.llm.body"))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(L10n.tr("settings.got_it")) {
                            settings.markLLMCleanupHelpSeen()
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button(L10n.tr("settings.llm.fix_last_text")) {
                    model.fixLastSavedNote()
                }
                .disabled(
                    model.lastSavedNoteURL == nil ||
                    model.phase == .recording ||
                    model.phase == .processing ||
                    model.isPreparingLLM ||
                    !model.isLLMConnected ||
                    model.selectedLLMModelName == nil
                )

                Toggle(L10n.tr("settings.llm.connect"), isOn: llmConnectionBinding)
                    .toggleStyle(.switch)
                    .disabled(model.phase == .recording || model.phase == .processing || model.isPreparingLLM)

                if model.isLLMConnected, !model.availableLLMModels.isEmpty {
                    Picker(L10n.tr("settings.llm.model"), selection: llmModelBinding) {
                        ForEach(model.availableLLMModels, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.isPreparingLLM)
                }

                Text(model.llmStatusText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.lastSavedNoteURL == nil {
                    Text(L10n.tr("settings.llm.no_saved_note"))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.isLLMConnected && model.availableLLMModels.isEmpty {
                    Text(L10n.tr("settings.llm.no_models_found"))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.isLLMConnected {
                    Text(L10n.tr("settings.llm.connect_first"))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
