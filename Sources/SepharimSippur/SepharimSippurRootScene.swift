import SwiftUI
import Foundation
import AppKit

public struct SepharimSippurRootScene: Scene {
    @StateObject private var settings: SettingsStore
    @StateObject private var model: AppModel
    @StateObject private var capturePanelController: CapturePanelController
    private let shortcutMonitor: GlobalShortcutMonitor

    public init() {
        let settings = SettingsStore()
        let model = AppModel(settings: settings)
        let capturePanelController = CapturePanelController()
        let shortcutMonitor = GlobalShortcutMonitor {
            model.requestCaptureToggle()
        }

        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        _capturePanelController = StateObject(wrappedValue: capturePanelController)
        self.shortcutMonitor = shortcutMonitor

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            ApplicationIconLoader.applyAppIcon()
            capturePanelController.installIfNeeded(model: model, settings: settings)
            capturePanelController.showCaptureWindow()
            shortcutMonitor.updateShortcut(settings.globalShortcut)
            shortcutMonitor.startIfNeeded()
            Task { @MainActor in
                await model.bootstrapDependenciesOnLaunch()
            }
        }
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                model: model,
                settings: settings,
                setGlobalShortcut: { shortcut in
                    settings.setGlobalShortcut(shortcut)
                    shortcutMonitor.updateShortcut(shortcut)
                }
            )
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowView(
                model: model,
                settings: settings,
                setGlobalShortcut: { shortcut in
                    settings.setGlobalShortcut(shortcut)
                    shortcutMonitor.updateShortcut(shortcut)
                }
            )
        }
        .commands {
            SepharimSippurCommands()
        }

        Window("About Sepharim Sippur", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
