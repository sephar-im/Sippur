import SwiftUI
import Foundation

public struct SepharimSippurRootScene: Scene {
    @StateObject private var settings: SettingsStore
    @StateObject private var model: AppModel
    private let shortcutMonitor: GlobalShortcutMonitor

    public init() {
        let settings = SettingsStore()
        let model = AppModel(settings: settings)
        let shortcutMonitor = GlobalShortcutMonitor {
            model.requestCaptureToggle()
        }

        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        self.shortcutMonitor = shortcutMonitor

        DispatchQueue.main.async {
            shortcutMonitor.startIfNeeded()
        }
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
