import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let setGlobalShortcut: (GlobalShortcutMonitor.Shortcut?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sepharim Sippur")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text("State: \(model.phase.title)")
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
                        Button("Retry Setup") {
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
               !model.llmStatusText.hasPrefix("LLM ready") {
                Button("Retry LLM Setup") {
                    model.retryLLMSetup()
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
