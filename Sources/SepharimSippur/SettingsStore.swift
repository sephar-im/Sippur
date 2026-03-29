import Foundation
import AppKit

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let outputFolderPath = "outputFolderPath"
        static let outputFormat = "outputFormat"
        static let outputMode = "outputMode"
        static let copySavedNoteToClipboard = "copySavedNoteToClipboard"
        static let hasSeenFirstUseHelp = "hasSeenFirstUseHelp"
        static let hasSeenLLMCleanupHelp = "hasSeenLLMCleanupHelp"
        static let llmPostProcessingEnabled = "llmPostProcessingEnabled"
        static let legacyPreferredLLMModel = "preferredLLMModel"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutCarbonModifiers = "shortcutCarbonModifiers"
        static let shortcutDisplayName = "shortcutDisplayName"
    }

    @Published var outputFormat: OutputFormat {
        didSet {
            userDefaults.set(outputFormat.rawValue, forKey: Keys.outputFormat)
        }
    }

    @Published var outputMode: OutputMode {
        didSet {
            userDefaults.set(outputMode.rawValue, forKey: Keys.outputMode)
        }
    }

    @Published private(set) var outputFolderURL: URL
    @Published private(set) var globalShortcut: GlobalShortcutMonitor.Shortcut?

    @Published var isLLMPostProcessingEnabled: Bool {
        didSet {
            userDefaults.set(isLLMPostProcessingEnabled, forKey: Keys.llmPostProcessingEnabled)
        }
    }

    @Published var copySavedNoteToClipboard: Bool {
        didSet {
            userDefaults.set(copySavedNoteToClipboard, forKey: Keys.copySavedNoteToClipboard)
        }
    }

    @Published private(set) var hasSeenFirstUseHelp: Bool {
        didSet {
            userDefaults.set(hasSeenFirstUseHelp, forKey: Keys.hasSeenFirstUseHelp)
        }
    }

    @Published private(set) var hasSeenLLMCleanupHelp: Bool {
        didSet {
            userDefaults.set(hasSeenLLMCleanupHelp, forKey: Keys.hasSeenLLMCleanupHelp)
        }
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        defaultOutputFolderURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager

        let storedPath = userDefaults.string(forKey: Keys.outputFolderPath)
        let defaultFolder = defaultOutputFolderURL ?? Self.defaultOutputFolder(fileManager: fileManager)

        outputFolderURL = storedPath.map(URL.init(fileURLWithPath:)) ?? defaultFolder
        outputFormat = OutputFormat(rawValue: userDefaults.string(forKey: Keys.outputFormat) ?? "") ?? .md
        outputMode = OutputMode(rawValue: userDefaults.string(forKey: Keys.outputMode) ?? "") ?? .normal
        if let storedKeyCode = userDefaults.object(forKey: Keys.shortcutKeyCode) as? NSNumber,
           let storedModifiers = userDefaults.object(forKey: Keys.shortcutCarbonModifiers) as? NSNumber,
           let storedDisplayName = userDefaults.string(forKey: Keys.shortcutDisplayName) {
            globalShortcut = GlobalShortcutMonitor.Shortcut(
                keyCode: storedKeyCode.uint32Value,
                carbonModifiers: storedModifiers.uint32Value,
                displayName: storedDisplayName
            )
        } else {
            globalShortcut = nil
        }
        isLLMPostProcessingEnabled = userDefaults.bool(forKey: Keys.llmPostProcessingEnabled)
        copySavedNoteToClipboard = userDefaults.bool(forKey: Keys.copySavedNoteToClipboard)
        hasSeenFirstUseHelp = userDefaults.bool(forKey: Keys.hasSeenFirstUseHelp)
        hasSeenLLMCleanupHelp = userDefaults.bool(forKey: Keys.hasSeenLLMCleanupHelp)

        userDefaults.removeObject(forKey: Keys.legacyPreferredLLMModel)

        ensureOutputFolderExists()
        persistOutputFolder()
    }

    var exportSettings: ExportSettings {
        ExportSettings(
            folderURL: outputFolderURL,
            format: outputFormat,
            mode: outputMode
        )
    }

    var outputFolderPath: String {
        outputFolderURL.path
    }

    var globalShortcutDisplayName: String {
        globalShortcut?.displayName ?? "Not set"
    }

    var llmPostProcessingSettings: LLMPostProcessingSettings {
        LLMPostProcessingSettings(
            isEnabled: isLLMPostProcessingEnabled,
            generatesTitle: outputFormat == .md,
            addsObsidianWikilinks: outputFormat == .md && outputMode == .obsidian
        )
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolderURL
        panel.prompt = "Choose Folder"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        setOutputFolder(selectedURL)
    }

    func setOutputFolder(_ url: URL) {
        outputFolderURL = url.standardizedFileURL
        ensureOutputFolderExists()
        persistOutputFolder()
    }

    func openOutputFolder() {
        ensureOutputFolderExists()
        NSWorkspace.shared.open(outputFolderURL)
    }

    func setGlobalShortcut(_ shortcut: GlobalShortcutMonitor.Shortcut?) {
        globalShortcut = shortcut

        if let shortcut {
            userDefaults.set(shortcut.keyCode, forKey: Keys.shortcutKeyCode)
            userDefaults.set(shortcut.carbonModifiers, forKey: Keys.shortcutCarbonModifiers)
            userDefaults.set(shortcut.displayName, forKey: Keys.shortcutDisplayName)
        } else {
            userDefaults.removeObject(forKey: Keys.shortcutKeyCode)
            userDefaults.removeObject(forKey: Keys.shortcutCarbonModifiers)
            userDefaults.removeObject(forKey: Keys.shortcutDisplayName)
        }
    }

    func markFirstUseHelpSeen() {
        hasSeenFirstUseHelp = true
    }

    func markLLMCleanupHelpSeen() {
        hasSeenLLMCleanupHelp = true
    }

    private func ensureOutputFolderExists() {
        try? fileManager.createDirectory(
            at: outputFolderURL,
            withIntermediateDirectories: true
        )
    }

    private func persistOutputFolder() {
        userDefaults.set(outputFolderURL.path, forKey: Keys.outputFolderPath)
    }

    private static func defaultOutputFolder(fileManager: FileManager) -> URL {
        let documentsFolder = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(component: "Documents", directoryHint: .isDirectory)
        return documentsFolder.appending(component: "Sepharim Sippur", directoryHint: .isDirectory)
    }
}
