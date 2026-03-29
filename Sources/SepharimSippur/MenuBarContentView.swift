import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let setGlobalShortcut: (GlobalShortcutMonitor.Shortcut?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("menu.title"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text(L10n.format("menu.state", model.phase.title))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if !model.isCaptureReady {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if model.isBootstrappingDependencies {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(model.statusText)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(model.detailText)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.hasBlockingSetupFailure {
                        Button(L10n.tr("menu.retry_setup")) {
                            model.retryDependencyBootstrap()
                        }
                    }
                }
            }

            Divider()

            SettingsSectionsView(
                model: model,
                settings: settings,
                setGlobalShortcut: setGlobalShortcut,
                showsFirstUseHelp: true,
                showsModeExplanation: false,
                showsAdvancedLLMControls: false
            )

            if settings.isLLMPostProcessingEnabled,
               model.isCaptureReady,
               !model.isPreparingLLM,
               !model.isLLMReady {
                Button(L10n.tr("menu.retry_llm_setup")) {
                    model.retryLLMSetup()
                }
            }

            Divider()

            Button(L10n.tr("menu.quit")) {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
