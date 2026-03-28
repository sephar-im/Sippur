import Foundation
import AppKit

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let outputFolderPath = "outputFolderPath"
        static let outputFormat = "outputFormat"
        static let outputMode = "outputMode"
        static let llmPostProcessingEnabled = "llmPostProcessingEnabled"
        static let llmGeneratesTitle = "llmGeneratesTitle"
        static let llmAddsObsidianWikilinks = "llmAddsObsidianWikilinks"
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

    @Published var isLLMPostProcessingEnabled: Bool {
        didSet {
            userDefaults.set(isLLMPostProcessingEnabled, forKey: Keys.llmPostProcessingEnabled)
        }
    }

    @Published var llmGeneratesTitle: Bool {
        didSet {
            userDefaults.set(llmGeneratesTitle, forKey: Keys.llmGeneratesTitle)
        }
    }

    @Published var llmAddsObsidianWikilinks: Bool {
        didSet {
            userDefaults.set(llmAddsObsidianWikilinks, forKey: Keys.llmAddsObsidianWikilinks)
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
        isLLMPostProcessingEnabled = userDefaults.bool(forKey: Keys.llmPostProcessingEnabled)
        llmGeneratesTitle = userDefaults.bool(forKey: Keys.llmGeneratesTitle)
        llmAddsObsidianWikilinks = userDefaults.bool(forKey: Keys.llmAddsObsidianWikilinks)

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

    var llmPostProcessingSettings: LLMPostProcessingSettings {
        LLMPostProcessingSettings(
            isEnabled: isLLMPostProcessingEnabled,
            generatesTitle: llmGeneratesTitle,
            addsObsidianWikilinks: llmAddsObsidianWikilinks
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
