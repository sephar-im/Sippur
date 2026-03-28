import Foundation
import XCTest
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
        return try stopResult.get()
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "Test failure" }
}

@MainActor
private final class MockTranscriptionService: TranscriptionServicing {
    var transcribeCalls = 0
    var lastAudioURL: URL?
    var result: Result<String, Error> = .success("Transcribed words")

    func transcribeAudio(at audioURL: URL) async throws -> String {
        transcribeCalls += 1
        lastAudioURL = audioURL
        return try result.get()
    }
}

private final class MockNoteExporter: NoteExporting {
    var saveCalls = 0
    var lastTranscription: String?
    var lastSettings: ExportSettings?
    var result: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/test-note.md"))

    func saveNote(transcription: String, using settings: ExportSettings, date: Date) throws -> URL {
        saveCalls += 1
        lastTranscription = transcription
        lastSettings = settings
        return try result.get()
    }
}

final class SepharimSippurTests: XCTestCase {
    @MainActor
    func testAppModelStartsIdle() {
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(settings: makeTestSettingsStore(suiteName: suiteName, reset: true), recordingService: MockRecordingService())

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.statusText, "Click the circle to start recording.")
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

    func testTxtDraftUsesSortableFilenameAndPlainTextBody() {
        let settings = ExportSettings(
            folderURL: URL(fileURLWithPath: "/tmp/notes"),
            format: .txt,
            mode: .normal
        )
        let exporter = NoteExporter()
        let date = Date(timeIntervalSince1970: 0)

        let draft = exporter.buildNoteDraft(
            transcription: "Hello from Whisper.",
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
            transcription: "Hello from Whisper.",
            using: settings,
            date: date,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(draft.fileName, "1970-01-01 00-00-00.md")
        XCTAssertTrue(draft.contents.contains("# 1970-01-01 00:00:00"))
        XCTAssertTrue(draft.contents.contains("Created: 1970-01-01 00:00:00"))
        XCTAssertTrue(draft.contents.contains("Hello from Whisper."))
        XCTAssertFalse(draft.contents.contains("[["))
    }

    @MainActor
    func testPrimaryActionStartsRecordingWhenPermissionIsGranted() async {
        let service = MockRecordingService()
        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(settings: makeTestSettingsStore(suiteName: suiteName, reset: true), recordingService: service)

        await model.performPrimaryAction()

        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.statusText, "Recording in progress.")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 0)
    }

    @MainActor
    func testRecordingFlowStopsIntoSuccess() async {
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

        await model.performPrimaryAction()
        await model.performPrimaryAction()

        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(model.statusText, "Saved test-note.md.")
        XCTAssertEqual(model.lastRecordingURL?.path, "/tmp/test-recording.wav")
        XCTAssertEqual(model.lastSavedNoteURL?.path, "/tmp/test-note.md")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
        XCTAssertEqual(transcriptionService.transcribeCalls, 1)
        XCTAssertEqual(transcriptionService.lastAudioURL?.path, "/tmp/test-recording.wav")
        XCTAssertEqual(exporter.saveCalls, 1)
        XCTAssertEqual(exporter.lastTranscription, "Transcribed words")
        XCTAssertEqual(exporter.lastSettings, settings.exportSettings)
    }

    @MainActor
    func testDeniedPermissionMovesToErrorState() async {
        let service = MockRecordingService()
        service.permissionGranted = false

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(settings: makeTestSettingsStore(suiteName: suiteName, reset: true), recordingService: service)

        await model.performPrimaryAction()

        XCTAssertEqual(model.phase, .error)
        XCTAssertTrue(model.statusText.contains("Microphone access was denied"))
        XCTAssertEqual(service.startCalls, 0)
    }

    @MainActor
    func testStopFailureLeavesAppStableInErrorState() async {
        let service = MockRecordingService()
        service.stopResult = .failure(TestFailure())

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(settings: makeTestSettingsStore(suiteName: suiteName, reset: true), recordingService: service)

        await model.performPrimaryAction()
        await model.performPrimaryAction()

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

        await model.performPrimaryAction()
        await model.performPrimaryAction()

        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.statusText, "Test failure")
        XCTAssertEqual(service.startCalls, 1)
        XCTAssertEqual(service.stopCalls, 1)
        XCTAssertEqual(transcriptionService.transcribeCalls, 1)
    }

    @MainActor
    func testDuplicateStartErrorBecomesErrorState() async {
        let service = MockRecordingService()
        service.startResult = .failure(RecordingService.RecordingError.alreadyRecording)

        let suiteName = "SepharimSippurTests.\(UUID().uuidString)"
        let model = AppModel(settings: makeTestSettingsStore(suiteName: suiteName, reset: true), recordingService: service)

        await model.performPrimaryAction()

        XCTAssertEqual(model.phase, .error)
        XCTAssertEqual(model.statusText, "A recording is already in progress.")
        XCTAssertEqual(service.startCalls, 1)
    }
}
