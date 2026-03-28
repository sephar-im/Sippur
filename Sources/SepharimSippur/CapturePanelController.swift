import AppKit
import SwiftUI

@MainActor
final class CapturePanelController: ObservableObject {
    private var panel: CapturePanel?
    private var hasPresentedInitialPanel = false
    private var dragStartOrigin: NSPoint?

    func installIfNeeded(model: AppModel) {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView: MainCaptureView(model: model, panelController: self))
        hostingView.frame = NSRect(x: 0, y: 0, width: 184, height: 184)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 184, height: 184),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .normal
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isExcludedFromWindowsMenu = true
        panel.center()

        self.panel = panel

        if !hasPresentedInitialPanel {
            hasPresentedInitialPanel = true
            showCaptureWindow()
        }
    }

    func showCaptureWindow() {
        guard let panel else { return }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func beginDragIfNeeded() {
        guard dragStartOrigin == nil, let panel else { return }
        dragStartOrigin = panel.frame.origin
    }

    func updateDrag(translation: CGSize) {
        guard let panel, let dragStartOrigin else { return }

        let newOrigin = NSPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        )
        panel.setFrameOrigin(newOrigin)
    }

    func endDrag() {
        dragStartOrigin = nil
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum ApplicationIconLoader {
    @MainActor
    static func applyAppIcon() {
        if let bundledIcon = loadBundledIcon() {
            NSApp.applicationIconImage = bundledIcon
            return
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(component: "sippur.png", directoryHint: .notDirectory)
        if let fallbackIcon = NSImage(contentsOf: fallbackURL) {
            NSApp.applicationIconImage = fallbackIcon
        }
    }

    private static func loadBundledIcon() -> NSImage? {
        let bundledIconURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("AppIcon.icns", isDirectory: false)
        return NSImage(contentsOf: bundledIconURL)
    }
}
