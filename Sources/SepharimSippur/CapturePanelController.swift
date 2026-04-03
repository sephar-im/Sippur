import AppKit
import SwiftUI

@MainActor
final class CapturePanelController: ObservableObject {
    private var panel: CapturePanel?
    private var hasPresentedInitialPanel = false
    private var activeSpaceObserver: NSObjectProtocol?

    func installIfNeeded(model: AppModel) {
        guard panel == nil else { return }

        let hostingView = CaptureHostingView(
            rootView: AnyView(MainCaptureView(model: model)),
            onActivate: {
                if model.hasBlockingSetupFailure {
                    model.retryDependencyBootstrap()
                    return
                }

                model.requestCaptureToggle()
            }
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: CaptureCircleView.panelSize, height: CaptureCircleView.panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: CaptureCircleView.panelSize, height: CaptureCircleView.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        panel.center()

        self.panel = panel
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.keepPanelVisible()
            }
        }

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

    private func keepPanelVisible() {
        guard let panel else { return }
        panel.orderFrontRegardless()
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class CaptureHostingView<Content: View>: NSHostingView<Content> {
    private let onActivate: () -> Void
    private var mouseDownLocationInScreen: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var isDragging = false

    init(rootView: Content, onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard shouldHandle(event: event) else { return }

        window?.makeKeyAndOrderFront(nil)
        mouseDownLocationInScreen = event.locationInScreen(in: window)
        mouseDownWindowOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let mouseDownLocationInScreen,
            let mouseDownWindowOrigin
        else {
            return
        }

        let currentLocationInScreen = event.locationInScreen(in: window)
        let deltaX = currentLocationInScreen.x - mouseDownLocationInScreen.x
        let deltaY = currentLocationInScreen.y - mouseDownLocationInScreen.y

        if !isDragging, hypot(deltaX, deltaY) < 2 {
            return
        }

        isDragging = true
        window.setFrameOrigin(
            NSPoint(
                x: mouseDownWindowOrigin.x + deltaX,
                y: mouseDownWindowOrigin.y + deltaY
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocationInScreen = nil
            mouseDownWindowOrigin = nil
            isDragging = false
        }

        guard shouldHandle(event: event) else { return }

        if !isDragging {
            onActivate()
        }
    }

    private func shouldHandle(event: NSEvent) -> Bool {
        let localPoint = convert(event.locationInWindow, from: nil)
        let radius = min(bounds.width, bounds.height) / 2
        let deltaX = localPoint.x - bounds.midX
        let deltaY = localPoint.y - bounds.midY
        return (deltaX * deltaX) + (deltaY * deltaY) <= (radius * radius)
    }
}

@MainActor
private extension NSEvent {
    func locationInScreen(in window: NSWindow?) -> NSPoint {
        if let window {
            return window.convertPoint(toScreen: locationInWindow)
        }

        return NSEvent.mouseLocation
    }
}

enum ApplicationIconLoader {
    @MainActor
    static func applyAppIcon() {
        if let applicationIcon = BrandImageLoader.applicationIcon() {
            NSApp.applicationIconImage = applicationIcon
        }
    }
}
