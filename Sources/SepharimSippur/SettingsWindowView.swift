import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    let setGlobalShortcut: (GlobalShortcutMonitor.Shortcut?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("settings.title"))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    Text(L10n.tr("settings.subtitle"))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                SettingsSectionsView(
                    model: model,
                    settings: settings,
                    setGlobalShortcut: setGlobalShortcut,
                    showsFirstUseHelp: false
                )
            }
            .padding(20)
        }
        .frame(minWidth: 430, idealWidth: 460, minHeight: 520, idealHeight: 560)
    }
}
