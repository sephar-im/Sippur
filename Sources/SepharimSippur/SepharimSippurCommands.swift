import SwiftUI

struct SepharimSippurCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sepharim Sippur") {
                openWindow(id: "about")
            }
        }
    }
}
