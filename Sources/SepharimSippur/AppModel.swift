import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var statusText = "Click the circle to start recording."
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
        self.settings = settings
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.noteExporter = noteExporter
        self.recordingService.unexpectedFailureHandler = { [weak self] error in
            self?.lastRecordingURL = nil
            self?.presentError(error.localizedDescription)
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

    func handlePrimaryAction() {
        Task {
            await performPrimaryAction()
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

    func performPrimaryAction() async {
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
        if phase == .success {
            lastRecordingURL = nil
            lastSavedNoteURL = nil
        }

        let permissionGranted = await recordingService.requestPermission()
        guard permissionGranted else {
            presentError("Microphone access was denied. Allow it in System Settings > Privacy & Security > Microphone.")
            return
        }

        do {
            let recordingURL = try recordingService.startRecording()
            phase = .recording
            statusText = "Recording in progress."
            detailText = "Temporary file: \(recordingURL.lastPathComponent)"
        } catch {
            presentError(error.localizedDescription)
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
            presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String) {
        phase = .error
        statusText = message
        detailText = "The app stayed stable. Click the circle to try recording again."
    }
}
