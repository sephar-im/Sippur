import SwiftUI

public struct SepharimSippurRootScene: Scene {
    @StateObject private var settings: SettingsStore
    @StateObject private var model: AppModel

    public init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
    }

    public var body: some Scene {
        WindowGroup(id: "capture") {
            MainCaptureView(model: model)
        }
        .defaultSize(width: 420, height: 460)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }

        MenuBarExtra("Sepharim Sippur", systemImage: model.menuBarSymbolName) {
            MenuBarContentView(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)
    }
}
