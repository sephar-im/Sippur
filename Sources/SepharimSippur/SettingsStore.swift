import Foundation
import AppKit

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let outputFolderPath = "outputFolderPath"
        static let whisperModel = "whisperModel"
        static let copySavedNoteToClipboard = "copySavedNoteToClipboard"
        static let hasSeenFirstUseHelp = "hasSeenFirstUseHelp"
        static let hasSeenLLMCleanupHelp = "hasSeenLLMCleanupHelp"
        static let legacyPreferredLLMModel = "preferredLLMModel"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutCarbonModifiers = "shortcutCarbonModifiers"
        static let shortcutDisplayName = "shortcutDisplayName"
    }

    @Published private(set) var outputFolderURL: URL
    @Published private(set) var globalShortcut: GlobalShortcutMonitor.Shortcut?
    @Published var whisperModel: WhisperModelChoice {
        didSet {
            userDefaults.set(whisperModel.rawValue, forKey: Keys.whisperModel)
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
        whisperModel = WhisperModelChoice(rawValue: userDefaults.string(forKey: Keys.whisperModel) ?? "") ?? .medium
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
        copySavedNoteToClipboard = userDefaults.bool(forKey: Keys.copySavedNoteToClipboard)
        hasSeenFirstUseHelp = userDefaults.bool(forKey: Keys.hasSeenFirstUseHelp)
        hasSeenLLMCleanupHelp = userDefaults.bool(forKey: Keys.hasSeenLLMCleanupHelp)

        userDefaults.removeObject(forKey: Keys.legacyPreferredLLMModel)
        userDefaults.removeObject(forKey: "llmPostProcessingEnabled")
        userDefaults.removeObject(forKey: "outputFormat")
        userDefaults.removeObject(forKey: "outputMode")

        ensureOutputFolderExists()
        persistOutputFolder()
    }

    var exportSettings: ExportSettings {
        ExportSettings(folderURL: outputFolderURL)
    }

    var outputFolderPath: String {
        outputFolderURL.path
    }

    var globalShortcutDisplayName: String {
        globalShortcut?.displayName ?? L10n.tr("global_shortcut.not_set")
    }

    func setWhisperModel(_ model: WhisperModelChoice) {
        whisperModel = model
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolderURL
        panel.prompt = L10n.tr("settings.notes.choose_folder")

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
