import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    private let idleStatusText = L10n.tr("app.idle.status")
    private let idleDetailText = L10n.tr("app.idle.detail")
    private let recoverableErrorDetailText = L10n.tr("app.recoverable_error_detail")
    private let bootstrapFailureDetailText = L10n.tr("app.bootstrap_failure_detail")

    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var statusText: String
    @Published private(set) var detailText: String
    @Published private(set) var lastSavedNoteURL: URL?
    @Published private(set) var isCaptureReady = false
    @Published private(set) var isBootstrappingDependencies = false
    @Published private(set) var hasBlockingSetupFailure = false
    @Published private(set) var llmStatusText = L10n.tr("app.llm.disabled")
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
            llmStatusText = L10n.format("app.llm.setup_after_transcription", LocalLLMModel.cleanupModel.label)
        }
    }

    var isLLMReady: Bool {
        preparedLLMModel != nil
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
            llmStatusText = L10n.tr("app.llm.disabled")
            isPreparingLLM = false
            return
        }

        guard isCaptureReady else {
            llmStatusText = L10n.format("app.llm.setup_after_transcription", LocalLLMModel.cleanupModel.label)
            return
        }

        Task {
            await refreshLLMAvailability()
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
            transitionToError(L10n.tr("app.error.microphone_denied"))
            return
        }

        do {
            _ = try recordingService.startRecording()
            clearSessionArtifacts()
            phase = .recording
            statusText = L10n.tr("app.status.listening")
            detailText = L10n.tr("app.detail.speak_finish")
        } catch {
            transitionToError(error.localizedDescription)
        }
    }

    private func stopRecording() async {
        phase = .processing
        statusText = L10n.tr("app.status.processing_note")
        detailText = L10n.tr("app.detail.transcribing_locally")

        do {
            let recordingURL = try await recordingService.stopRecording()
            defer {
                cleanupTemporaryAudio(at: recordingURL)
            }

            statusText = L10n.tr("app.status.transcribing_whisper")
            detailText = L10n.tr("app.detail.turning_speech_into_text")

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
                    preparedLLMModel = .cleanupModel
                    llmStatusText = L10n.format("app.llm.ready_model", LocalLLMModel.cleanupModel.label)
                } catch {
                    usedLLMFallback = true
                    noteContent = .whisperOnly(body: transcription)
                    preparedLLMModel = nil
                    llmStatusText = L10n.tr("app.llm.unavailable_fallback")
                }
            }

            isPreparingLLM = false
            statusText = L10n.tr("app.status.saving_note")
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
                    ? L10n.format("app.status.saved_and_copied", noteURL.lastPathComponent)
                    : L10n.format("app.status.saved_whisper_only", noteURL.lastPathComponent)
            } else {
                statusText = settings.copySavedNoteToClipboard
                    ? L10n.format("app.status.saved_and_copied", noteURL.lastPathComponent)
                    : L10n.format("app.status.saved", noteURL.lastPathComponent)
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
        statusText = L10n.tr("app.status.preparing_local_transcription")
        detailText = L10n.tr("app.detail.checking_whisper_assets")

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
            llmStatusText = L10n.tr("app.llm.disabled")
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
            llmStatusText = L10n.format("app.llm.ready_model", preparedModel.label)
        } catch {
            preparedLLMModel = nil
            llmStatusText = L10n.tr("app.llm.unavailable_fallback")
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
            settings.isLLMPostProcessingEnabled = false
            llmStatusText = L10n.format("app.llm.removed_and_disabled", removedModel.label)
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
