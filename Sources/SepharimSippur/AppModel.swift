import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    private let idleStatusText = "Click the circle or press \(GlobalShortcutMonitor.defaultShortcutDisplayName) to start recording."
    private let idleDetailText = "Recording will be transcribed locally and saved automatically when it stops."
    private let recoverableErrorDetailText = "The app stayed stable. Click the circle or press \(GlobalShortcutMonitor.defaultShortcutDisplayName) to try recording again."
    private let bootstrapFailureDetailText = "Local transcription setup did not finish. Retry setup to keep the app ready for fast capture."

    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var statusText: String
    @Published private(set) var detailText: String
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var lastSavedNoteURL: URL?
    @Published private(set) var isCaptureReady = false
    @Published private(set) var isBootstrappingDependencies = false
    @Published private(set) var hasBlockingSetupFailure = false
    @Published private(set) var llmStatusText = "LLM cleanup is disabled."
    @Published private(set) var isPreparingLLM = false

    let settings: SettingsStore
    private let recordingService: RecordingServicing
    private let transcriptionService: TranscriptionServicing
    private let llmPostProcessingService: LLMPostProcessingServicing
    private let noteExporter: NoteExporting
    private var isPerformingPrimaryAction = false
    private var hasStartedDependencyBootstrap = false

    init(
        settings: SettingsStore,
        recordingService: RecordingServicing = RecordingService(),
        transcriptionService: TranscriptionServicing = WhisperTranscriptionService(),
        llmPostProcessingService: LLMPostProcessingServicing = OllamaPostProcessingService(),
        noteExporter: NoteExporting = NoteExporter()
    ) {
        self.statusText = idleStatusText
        self.detailText = idleDetailText
        self.settings = settings
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.llmPostProcessingService = llmPostProcessingService
        self.noteExporter = noteExporter
        self.recordingService.unexpectedFailureHandler = { [weak self] error in
            self?.lastRecordingURL = nil
            self?.transitionToError(error.localizedDescription)
        }

        if settings.isLLMPostProcessingEnabled {
            llmStatusText = "LLM setup will start after transcription is ready."
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

    func bootstrapDependenciesOnLaunch() async {
        guard !hasStartedDependencyBootstrap else { return }
        hasStartedDependencyBootstrap = true

        await bootstrapRequiredDependencies()

        if isCaptureReady, settings.llmPostProcessingSettings.isEnabled {
            await prepareLLMIfNeeded()
        }
    }

    func retryDependencyBootstrap() {
        Task {
            await bootstrapRequiredDependencies()

            if isCaptureReady, settings.llmPostProcessingSettings.isEnabled {
                await prepareLLMIfNeeded()
            }
        }
    }

    func setLLMPostProcessingEnabled(_ isEnabled: Bool) {
        settings.isLLMPostProcessingEnabled = isEnabled
        if !isEnabled {
            llmStatusText = "LLM cleanup is disabled."
            isPreparingLLM = false
            return
        }

        guard isCaptureReady else {
            llmStatusText = "LLM setup will start after transcription is ready."
            return
        }

        Task {
            await prepareLLMIfNeeded()
        }
    }

    func retryLLMSetup() {
        guard settings.llmPostProcessingSettings.isEnabled, isCaptureReady else { return }

        Task {
            await prepareLLMIfNeeded()
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
        guard isCaptureReady else { return }
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
            var noteContent = NoteContent.whisperOnly(body: transcription)
            var usedLLMFallback = false

            if settings.llmPostProcessingSettings.isEnabled {
                do {
                    noteContent = try await llmPostProcessingService.postProcess(
                        transcription: transcription,
                        exportSettings: settings.exportSettings,
                        llmSettings: settings.llmPostProcessingSettings,
                        progress: { [weak self] summary, detail in
                            self?.isPreparingLLM = true
                            self?.llmStatusText = summary
                            self?.statusText = summary
                            if let detail {
                                self?.detailText = detail
                            }
                        }
                    )
                    llmStatusText = "LLM ready."
                } catch {
                    usedLLMFallback = true
                    noteContent = .whisperOnly(body: transcription)
                    llmStatusText = "LLM unavailable. Whisper-only fallback will be used."
                }
            }

            isPreparingLLM = false
            statusText = "Saving transcribed note."
            detailText = settings.outputFolderURL.path

            let noteURL = try noteExporter.saveNote(
                content: noteContent,
                using: settings.exportSettings,
                date: .now
            )

            lastSavedNoteURL = noteURL
            phase = .success
            if usedLLMFallback {
                statusText = "Saved \(noteURL.lastPathComponent). Used Whisper transcription only."
            } else {
                statusText = "Saved \(noteURL.lastPathComponent)."
            }
            detailText = noteURL.path
        } catch {
            isPreparingLLM = false
            transitionToError(error.localizedDescription)
        }
    }

    private func clearSessionArtifacts() {
        lastRecordingURL = nil
        lastSavedNoteURL = nil
    }

    private func bootstrapRequiredDependencies() async {
        guard !isBootstrappingDependencies else { return }

        isBootstrappingDependencies = true
        hasBlockingSetupFailure = false
        phase = .processing
        statusText = "Preparing local transcription."
        detailText = "Checking Whisper assets."

        do {
            try await transcriptionService.prepare(
                progress: { [weak self] summary, detail in
                    self?.statusText = summary
                    if let detail {
                        self?.detailText = detail
                    }
                }
            )

            isCaptureReady = true
            hasBlockingSetupFailure = false
            phase = .idle
            statusText = idleStatusText
            detailText = idleDetailText
        } catch {
            isCaptureReady = false
            hasBlockingSetupFailure = true
            phase = .error
            statusText = error.localizedDescription
            detailText = bootstrapFailureDetailText
        }

        isBootstrappingDependencies = false
    }

    private func transitionToError(_ message: String) {
        phase = .error
        statusText = message
        detailText = recoverableErrorDetailText
    }

    private func prepareLLMIfNeeded() async {
        guard settings.llmPostProcessingSettings.isEnabled else {
            llmStatusText = "LLM cleanup is disabled."
            isPreparingLLM = false
            return
        }

        guard !isPreparingLLM else { return }
        isPreparingLLM = true

        do {
            _ = try await llmPostProcessingService.prepare(
                settings: settings.llmPostProcessingSettings,
                progress: { [weak self] summary, detail in
                    self?.llmStatusText = summary
                    _ = detail
                }
            )
            llmStatusText = "LLM ready."
        } catch {
            llmStatusText = "LLM unavailable. Whisper-only fallback will be used."
        }

        isPreparingLLM = false
    }
}
