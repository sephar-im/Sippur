import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    private let idleStatusText = "Click the circle to capture a note."
    private let idleDetailText = "Speak, click again to finish, and the text note will save automatically."
    private let recoverableErrorDetailText = "The app stayed stable. Click the circle to try again."
    private let bootstrapFailureDetailText = "Local transcription setup did not finish. Retry setup to keep the app ready for fast capture."

    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var statusText: String
    @Published private(set) var detailText: String
    @Published private(set) var lastSavedNoteURL: URL?
    @Published private(set) var isCaptureReady = false
    @Published private(set) var isBootstrappingDependencies = false
    @Published private(set) var hasBlockingSetupFailure = false
    @Published private(set) var llmStatusText = "LLM cleanup is disabled."
    @Published private(set) var isPreparingLLM = false
    @Published private(set) var isOllamaInstalled = false
    @Published private(set) var preparedLLMModel: LocalLLMModel?

    let settings: SettingsStore
    private let recordingService: RecordingServicing
    private let transcriptionService: TranscriptionServicing
    private let llmPostProcessingService: LLMPostProcessingServicing
    private let noteExporter: NoteExporting
    private let clipboardWriter: ClipboardWriting
    private var isPerformingPrimaryAction = false
    private var hasStartedDependencyBootstrap = false
    private var successResetTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        recordingService: RecordingServicing = RecordingService(),
        transcriptionService: TranscriptionServicing = WhisperTranscriptionService(),
        llmPostProcessingService: LLMPostProcessingServicing = OllamaPostProcessingService(),
        noteExporter: NoteExporting = NoteExporter(),
        clipboardWriter: ClipboardWriting = SystemClipboardWriter()
    ) {
        self.statusText = idleStatusText
        self.detailText = idleDetailText
        self.settings = settings
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.llmPostProcessingService = llmPostProcessingService
        self.noteExporter = noteExporter
        self.clipboardWriter = clipboardWriter
        self.recordingService.unexpectedFailureHandler = { [weak self] error in
            self?.transitionToError(error.localizedDescription)
        }

        if settings.isLLMPostProcessingEnabled {
            llmStatusText = "LLM setup will start after transcription is ready."
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

        await refreshLLMAvailability()
        await bootstrapRequiredDependencies()

        if isCaptureReady, settings.llmPostProcessingSettings.isEnabled {
            await prepareLLMIfNeeded()
        }
    }

    func retryDependencyBootstrap() {
        Task {
            await refreshLLMAvailability()
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
            await refreshLLMAvailability()
            await prepareLLMIfNeeded()
        }
    }

    func setPreferredLLMModel(_ model: LocalLLMModel?) {
        settings.preferredLLMModel = model

        guard settings.llmPostProcessingSettings.isEnabled, isCaptureReady else { return }

        Task {
            await prepareLLMIfNeeded()
        }
    }

    func retryLLMSetup() {
        guard settings.llmPostProcessingSettings.isEnabled, isCaptureReady else { return }

        Task {
            await refreshLLMAvailability()
            await prepareLLMIfNeeded()
        }
    }

    func removeDownloadedLLM() {
        guard !isPreparingLLM else { return }

        Task {
            await removeSelectedLLM()
        }
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
        cancelPendingSuccessReset()

        let permissionGranted = await recordingService.requestPermission()
        guard permissionGranted else {
            transitionToError("Microphone access was denied. Allow it in System Settings > Privacy & Security > Microphone.")
            return
        }

        do {
            _ = try recordingService.startRecording()
            clearSessionArtifacts()
            phase = .recording
            statusText = "Listening."
            detailText = "Speak and click again to finish."
        } catch {
            transitionToError(error.localizedDescription)
        }
    }

    private func stopRecording() async {
        phase = .processing
        statusText = "Processing note."
        detailText = "Transcribing locally."

        do {
            let recordingURL = try await recordingService.stopRecording()
            defer {
                cleanupTemporaryAudio(at: recordingURL)
            }

            statusText = "Transcribing locally with Whisper."
            detailText = "Turning speech into text."

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
                    if let preferredLLMModel = settings.preferredLLMModel {
                        preparedLLMModel = preferredLLMModel
                        llmStatusText = "LLM ready (\(preferredLLMModel.label))."
                    } else if let preparedLLMModel {
                        llmStatusText = "LLM ready (\(preparedLLMModel.label))."
                    } else {
                        llmStatusText = "LLM ready."
                    }
                } catch {
                    usedLLMFallback = true
                    noteContent = .whisperOnly(body: transcription)
                    preparedLLMModel = nil
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

            if settings.copySavedNoteToClipboard {
                copyToClipboard(noteContent.body)
            }

            lastSavedNoteURL = noteURL
            phase = .success
            if usedLLMFallback {
                statusText = settings.copySavedNoteToClipboard
                    ? "Saved \(noteURL.lastPathComponent) and copied the text."
                    : "Saved \(noteURL.lastPathComponent). Used Whisper transcription only."
            } else {
                statusText = settings.copySavedNoteToClipboard
                    ? "Saved \(noteURL.lastPathComponent) and copied the text."
                    : "Saved \(noteURL.lastPathComponent)."
            }
            detailText = noteURL.path
            settings.markFirstUseHelpSeen()
            scheduleReturnToIdleAfterSuccess()
        } catch {
            isPreparingLLM = false
            transitionToError(error.localizedDescription)
        }
    }

    private func clearSessionArtifacts() {
        lastSavedNoteURL = nil
    }

    private func scheduleReturnToIdleAfterSuccess() {
        cancelPendingSuccessReset()

        successResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            guard let self, phase == .success else { return }
            phase = .idle
            statusText = idleStatusText
            detailText = idleDetailText
        }
    }

    private func cancelPendingSuccessReset() {
        successResetTask?.cancel()
        successResetTask = nil
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

    private func refreshLLMAvailability() async {
        isOllamaInstalled = await llmPostProcessingService.isOllamaInstalled()
    }

    private func transitionToError(_ message: String) {
        cancelPendingSuccessReset()
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
            let preparedModel = try await llmPostProcessingService.prepare(
                settings: settings.llmPostProcessingSettings,
                progress: { [weak self] summary, detail in
                    self?.llmStatusText = summary
                    _ = detail
                }
            )
            self.preparedLLMModel = preparedModel
            llmStatusText = "LLM ready (\(preparedModel.label))."
        } catch {
            preparedLLMModel = nil
            llmStatusText = "LLM unavailable. Whisper-only fallback will be used."
        }

        isPreparingLLM = false
    }

    private func removeSelectedLLM() async {
        isPreparingLLM = true

        do {
            let removedModel = try await llmPostProcessingService.removeModel(
                settings: settings.llmPostProcessingSettings,
                progress: { [weak self] summary, detail in
                    self?.llmStatusText = summary
                    _ = detail
                }
            )
            preparedLLMModel = nil
            settings.preferredLLMModel = nil
            settings.isLLMPostProcessingEnabled = false
            llmStatusText = "Removed \(removedModel.label). LLM cleanup is disabled."
        } catch {
            llmStatusText = error.localizedDescription
        }

        isPreparingLLM = false
    }

    private func copyToClipboard(_ text: String) {
        clipboardWriter.write(text)
    }

    private func cleanupTemporaryAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
