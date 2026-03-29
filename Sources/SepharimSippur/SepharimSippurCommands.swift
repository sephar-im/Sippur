import SwiftUI

struct SepharimSippurCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.tr("commands.about")) {
                openWindow(id: "about")
            }
        }
    }
}
