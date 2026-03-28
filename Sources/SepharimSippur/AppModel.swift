import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    private let idleStatusText = "Click the circle or press \(GlobalShortcutMonitor.defaultShortcutDisplayName) to start recording."
    private let recoverableErrorDetailText = "The app stayed stable. Click the circle or press \(GlobalShortcutMonitor.defaultShortcutDisplayName) to try recording again."

    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var statusText: String
    @Published private(set) var detailText = "Recording will be transcribed locally and saved automatically when it stops."
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var lastSavedNoteURL: URL?

    let settings: SettingsStore
    private let recordingService: RecordingServicing
    private let transcriptionService: TranscriptionServicing
    private let noteExporter: NoteExporting
    private var isPerformingPrimaryAction = false

    init(
        settings: SettingsStore,
        recordingService: RecordingServicing = RecordingService(),
        transcriptionService: TranscriptionServicing = WhisperTranscriptionService(),
        noteExporter: NoteExporting = NoteExporter()
    ) {
        self.statusText = idleStatusText
        self.settings = settings
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.noteExporter = noteExporter
        self.recordingService.unexpectedFailureHandler = { [weak self] error in
            self?.lastRecordingURL = nil
            self?.transitionToError(error.localizedDescription)
        }
    }

    var menuBarSymbolName: String {
        switch phase {
        case .recording:
            return "record.circle.fill"
        case .processing:
            return "hourglass.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        case .idle:
            return "mic.circle.fill"
        }
    }

    func requestCaptureToggle() {
        Task {
            await performCaptureToggle()
        }
    }

    func revealLastRecording() {
        guard let lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecordingURL])
    }

    func revealLastSavedNote() {
        guard let lastSavedNoteURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSavedNoteURL])
    }

    func performCaptureToggle() async {
        guard !isPerformingPrimaryAction else { return }
        isPerformingPrimaryAction = true
        defer { isPerformingPrimaryAction = false }

        switch phase {
        case .processing:
            return
        case .recording:
            await stopRecording()
        case .idle, .success, .error:
            await startRecording()
        }
    }

    private func startRecording() async {
        let permissionGranted = await recordingService.requestPermission()
        guard permissionGranted else {
            transitionToError("Microphone access was denied. Allow it in System Settings > Privacy & Security > Microphone.")
            return
        }

        do {
            let recordingURL = try recordingService.startRecording()
            clearSessionArtifacts()
            phase = .recording
            statusText = "Recording in progress."
            detailText = "Temporary file: \(recordingURL.lastPathComponent)"
        } catch {
            transitionToError(error.localizedDescription)
        }
    }

    private func stopRecording() async {
        phase = .processing
        statusText = "Finalizing recording."
        detailText = "Writing the temporary audio file."

        do {
            let recordingURL = try await recordingService.stopRecording()
            lastRecordingURL = recordingURL

            statusText = "Transcribing locally with Whisper."
            detailText = recordingURL.lastPathComponent

            let transcription = try await transcriptionService.transcribeAudio(at: recordingURL)

            statusText = "Saving transcribed note."
            detailText = settings.outputFolderURL.path

            let noteURL = try noteExporter.saveNote(
                transcription: transcription,
                using: settings.exportSettings,
                date: .now
            )

            lastSavedNoteURL = noteURL
            phase = .success
            statusText = "Saved \(noteURL.lastPathComponent)."
            detailText = noteURL.path
        } catch {
            transitionToError(error.localizedDescription)
        }
    }

    private func clearSessionArtifacts() {
        lastRecordingURL = nil
        lastSavedNoteURL = nil
    }

    private func transitionToError(_ message: String) {
        phase = .error
        statusText = message
        detailText = recoverableErrorDetailText
    }
}
