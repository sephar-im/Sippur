import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    let setGlobalShortcut: (GlobalShortcutMonitor.Shortcut?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    Text("Control where notes are saved, how they are formatted, and whether optional local cleanup is used.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                SettingsSectionsView(
                    model: model,
                    settings: settings,
                    setGlobalShortcut: setGlobalShortcut,
                    showsFirstUseHelp: false,
                    showsModeExplanation: true,
                    showsAdvancedLLMControls: true
                )
            }
            .padding(20)
        }
        .frame(minWidth: 430, idealWidth: 460, minHeight: 520, idealHeight: 560)
    }
}
