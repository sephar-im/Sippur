import AppKit

@MainActor
enum BrandImageLoader {
    private static var cachedApplicationIcon: NSImage?
    private static var cachedMenuBarStatusIcon: NSImage?

    static func applicationIcon() -> NSImage? {
        if let cachedApplicationIcon {
            return cachedApplicationIcon
        }

        if let bundledIcon = loadBundledApplicationIcon() {
            cachedApplicationIcon = bundledIcon
            return bundledIcon
        }

        let fallbackIcon = generatedApplicationIcon()
        cachedApplicationIcon = fallbackIcon
        return fallbackIcon
    }

    static func menuBarStatusIcon() -> NSImage? {
        if let cachedMenuBarStatusIcon {
            return cachedMenuBarStatusIcon
        }

        let icon = generatedMenuBarStatusIcon()
        cachedMenuBarStatusIcon = icon
        return icon
    }

    private static func loadBundledApplicationIcon() -> NSImage? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            let workspaceIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
            if workspaceIcon.isValid {
                return workspaceIcon
            }
        }

        let bundledIconURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("AppIcon.icns", isDirectory: false)
        return NSImage(contentsOf: bundledIconURL)
    }

    private static func generatedApplicationIcon() -> NSImage? {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).setFill()
        let inset = size.width * 0.085
        let circleRect = NSRect(
            x: inset,
            y: inset,
            width: size.width - (inset * 2),
            height: size.height - (inset * 2)
        )
        NSBezierPath(ovalIn: circleRect).fill()

        return image
    }

    private static func generatedMenuBarStatusIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let circleRect = NSRect(x: 1.5, y: 1.5, width: 15, height: 15)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        NSColor(calibratedWhite: 0.72, alpha: 1.0).setStroke()
        let strokePath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.35, dy: 0.35))
        strokePath.lineWidth = 0.7
        strokePath.stroke()

        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 7.2,
            weight: .bold
        )

        guard
            let symbolImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfiguration)
        else {
            return image
        }

        let tintedImage = symbolImage.copy() as? NSImage ?? symbolImage
        tintedImage.lockFocus()
        NSColor(calibratedWhite: 0.16, alpha: 1.0).set()
        let symbolRect = NSRect(origin: .zero, size: tintedImage.size)
        symbolRect.fill(using: .sourceAtop)
        tintedImage.unlockFocus()

        let symbolOrigin = NSPoint(
            x: (size.width - tintedImage.size.width) / 2,
            y: (size.height - tintedImage.size.height) / 2 - 0.1
        )
        tintedImage.draw(at: symbolOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

        return image
    }
}
