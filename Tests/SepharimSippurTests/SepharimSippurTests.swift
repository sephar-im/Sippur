import Foundation
import XCTest
import Carbon.HIToolbox
@testable import SepharimSippur

@MainActor
private func makeTestSettingsStore(suiteName: String, reset: Bool = false) -> SettingsStore {
    let defaults = UserDefaults(suiteName: suiteName)!
    if reset {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let folderURL = FileManager.default.temporaryDirectory
        .appending(component: suiteName, directoryHint: .isDirectory)
        .appending(component: "Notes", directoryHint: .isDirectory)

    return SettingsStore(
        userDefaults: defaults,
        fileManager: .default,
        defaultOutputFolderURL: folderURL
    )
}

@MainActor
private final class MockRecordingService: RecordingServicing {
    var unexpectedFailureHandler: (@MainActor (any Error) -> Void)?
    var permissionGranted = true
    var startResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/test-recording.wav"))
    var stopResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/test-recording.wav"))
    var stopDelayNanoseconds: UInt64 = 0
    var startCalls = 0
    var stopCalls = 0

    func requestPermission() async -> Bool {
        permissionGranted
    }

    func startRecording() throws -> URL {
        startCalls += 1
        return try startResult.get()
    }

    func stopRecording() async throws -> URL {
        stopCalls += 1

        if stopDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: stopDelayNanoseconds)
        }

        return try stopResult.get()
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Test failure" }
}

@MainActor
private final class MockTranscriptionService: TranscriptionServicing {
    var prepareCalls = 0
    var transcribeCalls = 0
    var lastAudioURL: URL?
    var prepareResult: Result<Void, Error> = .success(())
    var result: Result<String, Error> = .success("Transcribed words")

    func prepare(progress: @escaping @MainActor (String, String?) -> Void) async throws {
        prepareCalls += 1
        progress("Checking local transcription.", "ggml-base.bin")
        try prepareResult.get()
    }

    func transcribeAudio(at audioURL: URL) async throws -> String {
        transcribeCalls += 1
        lastAudioURL = audioURL
        return try result.get()
    }
}

@MainActor
private final class MockLLMPostProcessingService: LLMPostProcessingServicing {
    var ollamaInstalled = true
    var prepareCalls = 0
    var removeCalls = 0
    var postProcessCalls = 0
    var preparedModel: LocalLLMModel = .qwen25_05b
    var removedModel: LocalLLMModel?
    var removeResult: Result<Void, Error> = .success(())
    var postProcessResult: Result<NoteContent, Error> = .success(
        NoteContent(body: "Cleaned transcription", title: "Cleaned Title")
    )

    func isOllamaInstalled() async -> Bool {
        ollamaInstalled
    }

    func prepare(
        settings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        prepareCalls += 1
        progress("LLM ready.", nil)
        return settings.preferredModel ?? preparedModel
    }

    func removeModel(
        settings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        removeCalls += 1
        let model = settings.preferredModel ?? preparedModel
        removedModel = model
        progress("Downloaded LLM removed.", nil)
        try removeResult.get()
        return model
    }

    func postProcess(
        transcription: String,
        exportSettings: ExportSettings,
        llmSettings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> NoteContent {
        postProcessCalls += 1
        progress("Cleaning transcription locally.", nil)
        return try postProcessResult.get()
    }
}

private final class MockNoteExporter: NoteExporting {
    var saveCalls = 0
    var lastContent: NoteContent?
    var lastSettings: ExportSettings?
    var result: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/test-note.md"))

    func saveNote(content: NoteContent, using settings: ExportSettings, date: Date) throws -> URL {
        saveCalls += 1
        lastContent = content
        lastSettings = settings
        return try result.get()
    }
}

@MainActor
private final class MockClipboardWriter: ClipboardWriting {
    private(set) var writes: [String] = []

    func write(_ text: String) {
        writes.append(text)
    }
}

final class SepharimSippurTests: XCTestCase {
    @MainActor
    func testAppModelStartsIdle() {
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(settings: makeTestSettingsStore(suiteName: suiteName, reset: true), recordingService: MockRecordingService())

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, "Click the circle to capture a note.")
    }

    @MainActor
    func testSettingsPersistFormatModeAndFolder() {
        let suiteName = "SepharimSippurTests.settings.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)
        let chosenFolder = FileManager.default.temporaryDirectory
            .appending(component: suiteName, directoryHint: .isDirectory)
            .appending(component: "Chosen", directoryHint: .isDirectory)

        store.outputFormat = .txt
        store.outputMode = .obsidian
        store.setOutputFolder(chosenFolder)

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertEqual(reloadedStore.outputFormat, .txt)
        XCTAssertEqual(reloadedStore.outputMode, .obsidian)
        XCTAssertEqual(reloadedStore.outputFolderURL, chosenFolder.standardizedFileURL)
    }

    @MainActor
    func testSettingsPersistOptionalShortcut() {
        let suiteName = "SepharimSippurTests.shortcut.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)
        let shortcut = GlobalShortcutMonitor.Shortcut(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey),
            displayName: "Command-Option-K"
        )

        store.setGlobalShortcut(shortcut)

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertEqual(reloadedStore.globalShortcut, shortcut)
        XCTAssertEqual(reloadedStore.globalShortcutDisplayName, "Command-Option-K")
    }

    @MainActor
    func testSettingsPersistPreferredLLMModel() {
        let suiteName = "SepharimSippurTests.preferred-llm.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)

        store.preferredLLMModel = .qwen25_15b

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertEqual(reloadedStore.preferredLLMModel, .qwen25_15b)
    }

    @MainActor
    func testSettingsPersistClipboardOption() {
        let suiteName = "SepharimSippurTests.clipboard.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)

        store.copySavedNoteToClipboard = true

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertTrue(reloadedStore.copySavedNoteToClipboard)
    }

    func testTxtDraftUsesSortableFilenameAndPlainTextBody() {
        let settings = ExportSettings(
            folderURL: URL(fileURLWithPath: "/tmp/notes"),
            format: .txt,
            mode: .normal
        )
        let exporter = NoteExporter()
        let date = Date(timeIntervalSince1970: 0)

        let draft = exporter.buildNoteDraft(
            content: .whisperOnly(body: "Hello from Whisper."),
            using: settings,
            date: date,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(draft.fileName, "1970-01-01 00-00-00.txt")
        XCTAssertEqual(draft.contents, "Hello from Whisper.\n")
    }

    func testMarkdownDraftUsesMinimalObsidianFormatting() {
        let settings = ExportSettings(
            folderURL: URL(fileURLWithPath: "/tmp/notes"),
            format: .md,
            mode: .obsidian
        )
        let exporter = NoteExporter()
        let date = Date(timeIntervalSince1970: 0)

        let draft = exporter.buildNoteDraft(
            content: .whisperOnly(body: "Hello from Whisper."),
            using: settings,
            date: date,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(draft.fileName, "1970-01-01 00-00-00.md")
        XCTAssertTrue(draft.contents.hasPrefix("---\ncreated: 1970-01-01 00:00:00\n---\n\n"))
        XCTAssertTrue(draft.contents.contains("# 1970-01-01 00:00:00"))
        XCTAssertTrue(draft.contents.contains("Hello from Whisper."))
        XCTAssertFalse(draft.contents.contains("[["))
    }

    func testMarkdownDraftUsesSimpleNormalFormatting() {
        let settings = ExportSettings(
            folderURL: URL(fileURLWithPath: "/tmp/notes"),
            format: .md,
            mode: .normal
        )
        let exporter = NoteExporter()
        let date = Date(timeIntervalSince1970: 0)

        let draft = exporter.buildNoteDraft(
            content: .whisperOnly(body: "Hello from Whisper."),
            using: settings,
            date: date,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(draft.fileName, "1970-01-01 00-00-00.md")
        XCTAssertTrue(draft.contents.contains("# Voice Note"))
        XCTAssertTrue(draft.contents.contains("Date: 1970-01-01 00:00:00"))
        XCTAssertTrue(draft.contents.contains("Hello from Whisper."))
        XCTAssertFalse(draft.contents.hasPrefix("---\n"))
    }

    func testSaveNoteAddsSuffixWhenTimestampedFileAlreadyExists() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appending(component: "SepharimSippurTests.\(UUID().uuidString)", directoryHint: .isDirectory)
        let settings = ExportSettings(folderURL: folderURL, format: .txt, mode: .normal)
        let exporter = NoteExporter()
        let date = Date(timeIntervalSince1970: 0)

        let firstURL = try exporter.saveNote(content: .whisperOnly(body: "First note"), using: settings, date: date)
        let secondURL = try exporter.saveNote(content: .whisperOnly(body: "Second note"), using: settings, date: date)

        XCTAssertTrue(firstURL.lastPathComponent.hasSuffix(".txt"))
        XCTAssertTrue(secondURL.lastPathComponent.hasSuffix(" 01.txt"))
        XCTAssertTrue(secondURL.lastPathComponent.hasPrefix(firstURL.deletingPathExtension().lastPathComponent))
        XCTAssertEqual(try String(contentsOf: firstURL), "First note\n")
        XCTAssertEqual(try String(contentsOf: secondURL), "Second note\n")
    }

    func testSaveNoteFailsWhenOutputFolderPathIsAFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appending(component: "SepharimSippurTests.\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fileURL = tempDirectory.appending(component: "not-a-folder", directoryHint: .notDirectory)
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let settings = ExportSettings(folderURL: fileURL, format: .txt, mode: .normal)
        let exporter = NoteExporter()

        XCTAssertThrowsError(try exporter.saveNote(content: .whisperOnly(body: "Hello"), using: settings, date: Date(timeIntervalSince1970: 0))) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The selected output path is not a folder: \(fileURL.path)"
            )
        }
    }

    func testModelSelectorUsesSmallerModelForLowAvailableMemory() {
        XCTAssertEqual(
            OllamaModelSelector.recommendedModel(availableMemoryBytes: 2 * 1024 * 1024 * 1024),
            .qwen25_05b
        )
    }

    func testModelSelectorUsesLargerModelWhenMemoryIsSufficient() {
        XCTAssertEqual(
            OllamaModelSelector.recommendedModel(availableMemoryBytes: 10 * 1024 * 1024 * 1024),
            .qwen25_15b
        )
    }

    @MainActor
    func testBootstrapOnLaunchPreparesTranscriptionAndReturnsToIdle() async {
        let transcriptionService = MockTranscriptionService()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: MockRecordingService(),
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()

        XCTAssertEqual(transcriptionService.prepareCalls, 1)
        XCTAssertTrue(model.isCaptureReady)
        XCTAssertFalse(model.hasBlockingSetupFailure)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, "Click the circle to capture a note.")
    }

    @MainActor
    func testBootstrapFailureBlocksCaptureUntilRetry() async {
        let recordingService = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        transcriptionService.prepareResult = .failure(TestFailure())
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: recordingService,
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()

        XCTAssertFalse(model.isCaptureReady)
        XCTAssertTrue(model.hasBlockingSetupFailure)
        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.statusText, "Test failure")
        XCTAssertEqual(recordingService.startCalls, 0)

        transcriptionService.prepareResult = .success(())
        model.retryDependencyBootstrap()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(model.isCaptureReady)
        XCTAssertFalse(model.hasBlockingSetupFailure)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor
    func testBootstrapOnLaunchPreparesOptionalLLMWhenEnabled() async {
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        settings.isLLMPostProcessingEnabled = true

        let model = AppModel(
            settings: settings,
            recordingService: MockRecordingService(),
            transcriptionService: transcriptionService,
            llmPostProcessingService: llmService
        )

        await model.bootstrapDependenciesOnLaunch()

        XCTAssertEqual(transcriptionService.prepareCalls, 1)
        XCTAssertEqual(llmService.prepareCalls, 1)
        XCTAssertEqual(model.llmStatusText, "LLM ready (Qwen 0.5B).")
    }

    @MainActor
    func testSelectingPreferredLLMModelTriggersPreparationWhenEnabled() async {
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        llmService.preparedModel = .qwen25_05b
        let suiteName = "SepharimSippurTests.preferred-model.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        settings.isLLMPostProcessingEnabled = true

        let model = AppModel(
            settings: settings,
            recordingService: MockRecordingService(),
            transcriptionService: transcriptionService,
            llmPostProcessingService: llmService
        )

        await model.bootstrapDependenciesOnLaunch()
        model.setPreferredLLMModel(.qwen25_15b)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(settings.preferredLLMModel, .qwen25_15b)
        XCTAssertEqual(model.preparedLLMModel, .qwen25_15b)
        XCTAssertEqual(model.llmStatusText, "LLM ready (Qwen 1.5B).")
    }

    @MainActor
    func testRemoveDownloadedLLMUsesSelectedModel() async {
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        let suiteName = "SepharimSippurTests.remove-llm.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        settings.isLLMPostProcessingEnabled = true
        settings.preferredLLMModel = .qwen25_15b

        let model = AppModel(
            settings: settings,
            recordingService: MockRecordingService(),
            transcriptionService: transcriptionService,
            llmPostProcessingService: llmService
        )

        await model.bootstrapDependenciesOnLaunch()
        model.removeDownloadedLLM()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(llmService.removeCalls, 1)
        XCTAssertEqual(llmService.removedModel, .qwen25_15b)
        XCTAssertNil(model.preparedLLMModel)
        XCTAssertNil(settings.preferredLLMModel)
        XCTAssertFalse(settings.isLLMPostProcessingEnabled)
        XCTAssertEqual(model.llmStatusText, "Removed Qwen 1.5B. LLM cleanup is disabled.")
    }

    @MainActor
    func testPrimaryActionStartsRecordingWhenPermissionIsGranted() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: service,
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()

        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.statusText, "Listening.")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 0)
    }

    @MainActor
    func testRecordingFlowStopsIntoSuccess() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let exporter = MockNoteExporter()
        let clipboardWriter = MockClipboardWriter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        settings.copySavedNoteToClipboard = true
        let model = AppModel(
            settings: settings,
            recordingService: service,
            transcriptionService: transcriptionService,
            noteExporter: exporter,
            clipboardWriter: clipboardWriter
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()
        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.statusText, "Saved test-note.md and copied the text.")
        XCTAssertEqual(model.lastSavedNoteURL?.path, "/tmp/test-note.md")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
        XCTAssertEqual(transcriptionService.transcribeCalls, 1)
        XCTAssertEqual(transcriptionService.lastAudioURL?.path, "/tmp/test-recording.wav")
        XCTAssertEqual(exporter.saveCalls, 1)
        XCTAssertEqual(exporter.lastContent, .whisperOnly(body: "Transcribed words"))
        XCTAssertEqual(exporter.lastSettings, settings.exportSettings)
        XCTAssertEqual(clipboardWriter.writes, ["Transcribed words"])
    }

    @MainActor
    func testLLMPostProcessingEnabledUsesCleanedNoteContent() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        let exporter = MockNoteExporter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        settings.isLLMPostProcessingEnabled = true

        let model = AppModel(
            settings: settings,
            recordingService: service,
            transcriptionService: transcriptionService,
            llmPostProcessingService: llmService,
            noteExporter: exporter
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()
        await model.performCaptureToggle()

        XCTAssertEqual(llmService.postProcessCalls, 1)
        XCTAssertEqual(exporter.lastContent, NoteContent(body: "Cleaned transcription", title: "Cleaned Title"))
        XCTAssertEqual(model.statusText, "Saved test-note.md.")
    }

    @MainActor
    func testSuccessReturnsToIdleAfterBriefDelay() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let exporter = MockNoteExporter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        let model = AppModel(
            settings: settings,
            recordingService: service,
            transcriptionService: transcriptionService,
            noteExporter: exporter
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()
        await model.performCaptureToggle()
        XCTAssertEqual(model.phase, .success)

        try? await Task.sleep(nanoseconds: 1_400_000_000)

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, "Click the circle to capture a note.")
    }

    @MainActor
    func testDeniedPermissionMovesToErrorState() async {
        let service = MockRecordingService()
        service.permissionGranted = false
        let transcriptionService = MockTranscriptionService()

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: service,
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()

        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .error)
        XCTAssertTrue(model.statusText.contains("Microphone access was denied"))
        XCTAssertEqual(service.startCalls, 0)
    }

    @MainActor
    func testStopFailureLeavesAppStableInErrorState() async {
        let service = MockRecordingService()
        service.stopResult = .failure(TestFailure())
        let transcriptionService = MockTranscriptionService()

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: service,
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()
        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.statusText, "Test failure")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
    }

    @MainActor
    func testTranscriptionFailureLeavesAppStableInErrorState() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        transcriptionService.result = .failure(TestFailure())

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: service,
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()
        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.statusText, "Test failure")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
        XCTAssertEqual(transcriptionService.transcribeCalls, 1)
    }

    @MainActor
    func testLLMFailureFallsBackToWhisperAndStillSaves() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        llmService.postProcessResult = .failure(TestFailure())
        let exporter = MockNoteExporter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)
        settings.isLLMPostProcessingEnabled = true

        let model = AppModel(
            settings: settings,
            recordingService: service,
            transcriptionService: transcriptionService,
            llmPostProcessingService: llmService,
            noteExporter: exporter
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()
        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.statusText, "Saved test-note.md. Used Whisper transcription only.")
        XCTAssertEqual(exporter.lastContent, .whisperOnly(body: "Transcribed words"))
        XCTAssertEqual(llmService.postProcessCalls, 1)
    }

    @MainActor
    func testRepeatedStopToggleDoesNotDoubleTransition() async {
        let service = MockRecordingService()
        service.stopDelayNanoseconds = 50_000_000

        let transcriptionService = MockTranscriptionService()
        let exporter = MockNoteExporter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: service,
            transcriptionService: transcriptionService,
            noteExporter: exporter
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()

        let firstStop = Task { await model.performCaptureToggle() }
        await Task.yield()
        let secondStop = Task { await model.performCaptureToggle() }

        await firstStop.value
        await secondStop.value

        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
        XCTAssertEqual(transcriptionService.transcribeCalls, 1)
        XCTAssertEqual(exporter.saveCalls, 1)
        XCTAssertEqual(model.phase, .success)
    }

    @MainActor
    func testDuplicateStartErrorBecomesErrorState() async {
        let service = MockRecordingService()
        service.startResult = .failure(RecordingService.RecordingError.alreadyRecording)
        let transcriptionService = MockTranscriptionService()

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: service,
            transcriptionService: transcriptionService
        )

        await model.bootstrapDependenciesOnLaunch()
        await model.performCaptureToggle()

        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.statusText, "A recording is already in progress.")
        XCTAssertEqual(service.startCalls, 1)
    }
}
