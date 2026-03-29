import AppKit

enum MenuBarIconVariant: String {
    case lightMode = "sippur_bar_lightmode"
    case darkMode = "sippur_bar_darkmode"
}

@MainActor
enum BrandImageLoader {
    private static var cachedMenuBarIcons: [MenuBarIconVariant: NSImage] = [:]
    private static var cachedApplicationIcon: NSImage?

    static func applicationIcon() -> NSImage? {
        if let cachedApplicationIcon {
            return cachedApplicationIcon
        }

        if let bundledIcon = loadBundledApplicationIcon() {
            cachedApplicationIcon = bundledIcon
            return bundledIcon
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(component: "sippur.png", directoryHint: .notDirectory)
        let fallbackIcon = NSImage(contentsOf: fallbackURL)
        cachedApplicationIcon = fallbackIcon
        return fallbackIcon
    }

    static func menuBarIcon(for variant: MenuBarIconVariant) -> NSImage? {
        if let cachedMenuBarIcon = cachedMenuBarIcons[variant] {
            return cachedMenuBarIcon
        }

        if let bundledIcon = loadBundledMenuBarIcon(for: variant) {
            bundledIcon.isTemplate = false
            cachedMenuBarIcons[variant] = bundledIcon
            return bundledIcon
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(component: "\(variant.rawValue).svg", directoryHint: .notDirectory)
        let fallbackIcon = NSImage(contentsOf: fallbackURL)
        fallbackIcon?.isTemplate = false
        if let fallbackIcon {
            cachedMenuBarIcons[variant] = fallbackIcon
        }
        return fallbackIcon
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

    private static func loadBundledMenuBarIcon(for variant: MenuBarIconVariant) -> NSImage? {
        guard let resourceURL = Bundle.main.url(forResource: variant.rawValue, withExtension: "svg") else {
            return nil
        }

        return NSImage(contentsOf: resourceURL)
    }
}
