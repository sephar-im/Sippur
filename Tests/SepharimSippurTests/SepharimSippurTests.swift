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
    var lastModel: WhisperModelChoice?
    var reportedProgress: [Double] = []
    var installedModelsSet: Set<WhisperModelChoice> = [.medium]
    var prepareResult: Result<Void, Error> = .success(())
    var result: Result<String, Error> = .success("Transcribed words")

    func installedModels() -> Set<WhisperModelChoice> {
        installedModelsSet
    }

    func prepare(model: WhisperModelChoice, progress: @escaping @MainActor (String, String?) -> Void) async throws {
        prepareCalls += 1
        progress("Checking local transcription.", model.fileName)
        try prepareResult.get()
        installedModelsSet.insert(model)
    }

    func removeModel(_ model: WhisperModelChoice) throws {
        installedModelsSet.remove(model)
    }

    func transcribeAudio(
        at audioURL: URL,
        using model: WhisperModelChoice,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String {
        transcribeCalls += 1
        lastAudioURL = audioURL
        lastModel = model
        progress(0.42)
        reportedProgress.append(0.42)
        return try result.get()
    }
}

@MainActor
private final class MockLLMPostProcessingService: LLMPostProcessingServicing {
    var ollamaInstalled = true
    var prepareCalls = 0
    var removeCalls = 0
    var postProcessCalls = 0
    var preparedModel: LocalLLMModel = .qwen25_15b
    var removedModel: LocalLLMModel?
    var removeResult: Result<Void, Error> = .success(())
    var postProcessResult: Result<NoteContent, Error> = .success(
        NoteContent(body: "Cleaned transcription", title: "Cleaned Title")
    )

    func isOllamaInstalled() async -> Bool {
        ollamaInstalled
    }

    func prepare(
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        prepareCalls += 1
        progress("LLM ready.", nil)
        return preparedModel
    }

    func removeModel(
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        removeCalls += 1
        removedModel = preparedModel
        progress("Downloaded LLM removed.", nil)
        try removeResult.get()
        return preparedModel
    }

    func postProcess(
        transcription: String,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> NoteContent {
        postProcessCalls += 1
        progress("Cleaning transcription locally.", nil)
        return try postProcessResult.get()
    }
}

private final class MockNoteExporter: NoteExporting {
    var saveCalls = 0
    var saveFixedCalls = 0
    var lastContent: NoteContent?
    var lastFixedContent: NoteContent?
    var lastSettings: ExportSettings?
    var lastFixedBaseURL: URL?
    var result: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/test-note.txt"))
    var fixedResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/test-note fixed.txt"))

    func saveNote(content: NoteContent, using settings: ExportSettings, date: Date) throws -> URL {
        saveCalls += 1
        lastContent = content
        lastSettings = settings
        let url = try result.get()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (content.body + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func saveFixedNote(content: NoteContent, basedOn originalNoteURL: URL) throws -> URL {
        saveFixedCalls += 1
        lastFixedContent = content
        lastFixedBaseURL = originalNoteURL
        let url = try fixedResult.get()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (content.body + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
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
        let model = AppModel(
            settings: makeTestSettingsStore(suiteName: suiteName, reset: true),
            recordingService: MockRecordingService(),
            transcriptionService: MockTranscriptionService()
        )

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, L10n.tr("app.idle.status"))
    }

    @MainActor
    func testSettingsPersistFolder() {
        let suiteName = "SepharimSippurTests.settings.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)
        let chosenFolder = FileManager.default.temporaryDirectory
            .appending(component: suiteName, directoryHint: .isDirectory)
            .appending(component: "Chosen", directoryHint: .isDirectory)

        store.setWhisperModel(.largeV3)
        store.setOutputFolder(chosenFolder)

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertEqual(reloadedStore.outputFolderURL, chosenFolder.standardizedFileURL)
        XCTAssertEqual(reloadedStore.whisperModel, .largeV3)
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
    func testSettingsPersistClipboardOption() {
        let suiteName = "SepharimSippurTests.clipboard.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)

        store.copySavedNoteToClipboard = true

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertTrue(reloadedStore.copySavedNoteToClipboard)
    }

    @MainActor
    func testSettingsPersistLLMCleanupHelpFlag() {
        let suiteName = "SepharimSippurTests.llm-help.\(UUID().uuidString)"
        let store = makeTestSettingsStore(suiteName: suiteName, reset: true)

        store.markLLMCleanupHelpSeen()

        let reloadedStore = makeTestSettingsStore(suiteName: suiteName)
        XCTAssertTrue(reloadedStore.hasSeenLLMCleanupHelp)
    }

    func testTxtDraftUsesSortableFilenameAndPlainTextBody() {
        let settings = ExportSettings(folderURL: URL(fileURLWithPath: "/tmp/notes"))
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

    func testSaveNoteAddsSuffixWhenTimestampedFileAlreadyExists() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appending(component: "SepharimSippurTests.\(UUID().uuidString)", directoryHint: .isDirectory)
        let settings = ExportSettings(folderURL: folderURL)
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

        let settings = ExportSettings(folderURL: fileURL)
        let exporter = NoteExporter()

        XCTAssertThrowsError(try exporter.saveNote(content: .whisperOnly(body: "Hello"), using: settings, date: Date(timeIntervalSince1970: 0))) { error in
            XCTAssertEqual(
                error.localizedDescription,
                L10n.format("note_export.error.path_not_folder", fileURL.path)
            )
        }
    }

    func testFixedCleanupModelUsesQwen15B() {
        XCTAssertEqual(LocalLLMModel.cleanupModel, .qwen25_15b)
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

        XCTAssertEqual(transcriptionService.prepareCalls, 0)
        XCTAssertTrue(model.isCaptureReady)
        XCTAssertFalse(model.hasBlockingSetupFailure)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, L10n.tr("app.idle.status"))
    }

    @MainActor
    func testBootstrapFailureBlocksCaptureUntilRetry() async {
        let recordingService = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        transcriptionService.installedModelsSet = []
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
        XCTAssertEqual(model.statusText, L10n.format("app.whisper.not_ready", WhisperModelChoice.medium.title))
        XCTAssertEqual(recordingService.startCalls, 0)

        transcriptionService.prepareResult = .success(())
        model.retryDependencyBootstrap()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(transcriptionService.prepareCalls, 1)
        XCTAssertTrue(model.isCaptureReady)
        XCTAssertFalse(model.hasBlockingSetupFailure)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor
    func testBootstrapOnLaunchChecksLLMAvailabilityWithoutPreparingModel() async {
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)

        let model = AppModel(
            settings: settings,
            recordingService: MockRecordingService(),
            transcriptionService: transcriptionService,
            llmPostProcessingService: llmService
        )

        await model.bootstrapDependenciesOnLaunch()

        XCTAssertEqual(transcriptionService.prepareCalls, 0)
        XCTAssertEqual(llmService.prepareCalls, 0)
        XCTAssertEqual(model.llmStatusText, L10n.format("app.llm.manual_fix_available", LocalLLMModel.cleanupModel.label))
    }

    @MainActor
    func testRemoveDownloadedLLMUsesSelectedModel() async {
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        let suiteName = "SepharimSippurTests.remove-llm.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)

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
        XCTAssertEqual(model.llmStatusText, L10n.format("app.llm.removed_model", LocalLLMModel.cleanupModel.label))
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
        XCTAssertEqual(model.statusText, L10n.tr("app.status.listening"))
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
        XCTAssertEqual(model.statusText, L10n.format("app.status.saved_and_copied", "test-note.txt"))
        XCTAssertEqual(model.lastSavedNoteURL?.path, "/tmp/test-note.txt")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
        XCTAssertEqual(transcriptionService.transcribeCalls, 1)
        XCTAssertEqual(transcriptionService.lastAudioURL?.path, "/tmp/test-recording.wav")
        XCTAssertEqual(transcriptionService.reportedProgress, [0.42])
        XCTAssertEqual(exporter.saveCalls, 1)
        XCTAssertEqual(exporter.lastContent, .whisperOnly(body: "Transcribed words"))
        XCTAssertEqual(exporter.lastSettings, settings.exportSettings)
        XCTAssertEqual(clipboardWriter.writes, ["Transcribed words"])
    }

    @MainActor
    func testFixLastSavedNoteUsesCleanedContentAndCreatesFixedFile() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        let exporter = MockNoteExporter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)

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
        model.fixLastSavedNote()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(llmService.postProcessCalls, 1)
        XCTAssertEqual(exporter.saveFixedCalls, 1)
        XCTAssertEqual(exporter.lastFixedContent, NoteContent(body: "Cleaned transcription", title: "Cleaned Title"))
        XCTAssertEqual(exporter.lastFixedBaseURL?.path, "/tmp/test-note.txt")
        XCTAssertEqual(model.lastSavedNoteURL?.path, "/tmp/test-note fixed.txt")
        XCTAssertEqual(model.llmStatusText, L10n.format("app.llm.ready_model", LocalLLMModel.cleanupModel.label))
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
        XCTAssertEqual(model.statusText, L10n.tr("app.idle.status"))
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
        XCTAssertEqual(model.statusText, L10n.tr("app.error.microphone_denied"))
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
    func testFixLastSavedNoteFailureKeepsOriginalNoteAndRestoresIdle() async {
        let service = MockRecordingService()
        let transcriptionService = MockTranscriptionService()
        let llmService = MockLLMPostProcessingService()
        llmService.postProcessResult = .failure(TestFailure())
        let exporter = MockNoteExporter()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let settings = makeTestSettingsStore(suiteName: suiteName, reset: true)

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
        model.fixLastSavedNote()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.lastSavedNoteURL?.path, "/tmp/test-note.txt")
        XCTAssertEqual(exporter.saveFixedCalls, 0)
        XCTAssertEqual(llmService.postProcessCalls, 1)
        XCTAssertEqual(model.llmStatusText, "Test failure")
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
        XCTAssertEqual(model.statusText, L10n.tr("recording.error.already_recording"))
        XCTAssertEqual(service.startCalls, 1)
    }
}
