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

                Picker(L10n.tr("settings.notes.format"), selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Picker(L10n.tr("settings.notes.mode"), selection: $settings.outputMode) {
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

            section(L10n.tr("settings.section.llm")) {
                Button(settings.isLLMPostProcessingEnabled ? L10n.tr("settings.llm.disable") : L10n.tr("settings.llm.enable")) {
                    llmEnabledBinding.wrappedValue.toggle()
                }

                if settings.isLLMPostProcessingEnabled, !settings.hasSeenLLMCleanupHelp {
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

                Text(model.llmStatusText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsAdvancedLLMControls, settings.isLLMPostProcessingEnabled {
                    if model.isOllamaInstalled, model.preparedLLMModel != nil {
                        Text(L10n.format("settings.llm.uses_model", LocalLLMModel.cleanupModel.label))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(L10n.tr("settings.llm.remove_downloaded_model")) {
                            model.removeDownloadedLLM()
                        }
                        .disabled(model.isPreparingLLM)
                    } else if model.isOllamaInstalled {
                        Text(L10n.format("settings.llm.no_local_model", LocalLLMModel.cleanupModel.label))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L10n.tr("settings.llm.install_ollama"))
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
            return L10n.tr("settings.mode.explanation.normal")
        case .obsidian:
            return L10n.tr("settings.mode.explanation.obsidian")
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
