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
    @Published private(set) var whisperStatusText = ""
    @Published private(set) var installedWhisperModels: Set<WhisperModelChoice> = []
    @Published private(set) var llmStatusText = L10n.format("app.llm.manual_fix_available", LocalLLMModel.cleanupModel.label)
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

        refreshWhisperAvailability()
    }

    var isSelectedWhisperModelInstalled: Bool {
        installedWhisperModels.contains(settings.whisperModel)
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
    }

    func retryDependencyBootstrap() {
        Task {
            await downloadSelectedWhisperModelIfNeeded()
        }
    }

    func setWhisperModel(_ model: WhisperModelChoice) {
        guard settings.whisperModel != model else { return }
        settings.setWhisperModel(model)
        refreshWhisperAvailability()
    }

    func downloadSelectedWhisperModel() {
        Task {
            await downloadSelectedWhisperModelIfNeeded()
        }
    }

    func removeSelectedWhisperModel() {
        guard !isBootstrappingDependencies else { return }
        guard phase != .recording, phase != .processing else { return }

        do {
            try transcriptionService.removeModel(settings.whisperModel)
            refreshWhisperAvailability()
        } catch {
            transitionToError(error.localizedDescription)
        }
    }

    func removeDownloadedLLM() {
        guard !isPreparingLLM else { return }

        Task {
            await removeSelectedLLM()
        }
    }

    func fixLastSavedNote() {
        guard !isPreparingLLM else { return }
        guard phase != .recording, phase != .processing else { return }
        guard lastSavedNoteURL != nil else {
            llmStatusText = L10n.tr("app.llm.no_saved_note")
            return
        }

        Task {
            await fixLastSavedNoteIfNeeded()
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

            let transcription = try await transcriptionService.transcribeAudio(
                at: recordingURL,
                using: settings.whisperModel,
                progress: { [weak self] progress in
                    let percentage = Int(max(0, min(progress * 100, 100)).rounded())
                    self?.detailText = L10n.format("app.detail.whisper_progress", percentage)
                }
            )
            let noteContent = NoteContent.whisperOnly(body: transcription)
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
            statusText = settings.copySavedNoteToClipboard
                ? L10n.format("app.status.saved_and_copied", noteURL.lastPathComponent)
                : L10n.format("app.status.saved", noteURL.lastPathComponent)
            detailText = noteURL.path
            settings.markFirstUseHelpSeen()
            scheduleReturnToIdleAfterSuccess()
        } catch {
            isPreparingLLM = false
            transitionToError(error.localizedDescription)
        }
    }

    private func scheduleReturnToIdleAfterSuccess() {
        cancelPendingSuccessReset()

        successResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            guard let self, phase == .success else { return }
            refreshWhisperAvailability()
        }
    }

    private func cancelPendingSuccessReset() {
        successResetTask?.cancel()
        successResetTask = nil
    }

    private func bootstrapRequiredDependencies() async {
        guard !isBootstrappingDependencies else { return }
        refreshWhisperAvailability()
    }

    private func refreshLLMAvailability() async {
        isOllamaInstalled = await llmPostProcessingService.isOllamaInstalled()
        if preparedLLMModel != nil {
            llmStatusText = L10n.format("app.llm.ready_model", LocalLLMModel.cleanupModel.label)
        } else if isOllamaInstalled {
            llmStatusText = L10n.format("app.llm.manual_fix_available", LocalLLMModel.cleanupModel.label)
        } else {
            llmStatusText = L10n.tr("app.llm.install_ollama")
        }
    }

    private func transitionToError(_ message: String) {
        cancelPendingSuccessReset()
        phase = .error
        statusText = message
        detailText = recoverableErrorDetailText
    }

    private func removeSelectedLLM() async {
        isPreparingLLM = true

        do {
            let removedModel = try await llmPostProcessingService.removeModel(
                progress: { [weak self] summary, detail in
                    self?.llmStatusText = summary
                    _ = detail
                }
            )
            preparedLLMModel = nil
            llmStatusText = L10n.format("app.llm.removed_model", removedModel.label)
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

    private func downloadSelectedWhisperModelIfNeeded() async {
        guard !isBootstrappingDependencies else { return }

        if isSelectedWhisperModelInstalled {
            refreshWhisperAvailability()
            return
        }

        cancelPendingSuccessReset()
        isBootstrappingDependencies = true
        hasBlockingSetupFailure = false
        phase = .processing
        statusText = L10n.format("app.whisper.preparing_model", settings.whisperModel.title)
        detailText = settings.whisperModel.fileName

        defer {
            isBootstrappingDependencies = false
        }

        do {
            try await transcriptionService.prepare(
                model: settings.whisperModel,
                progress: { [weak self] summary, detail in
                    self?.statusText = summary
                    if let detail {
                        self?.detailText = detail
                    }
                }
            )

            refreshWhisperAvailability()

            if isCaptureReady {
                phase = .idle
                statusText = idleStatusText
                detailText = idleDetailText
            }
        } catch {
            refreshWhisperAvailability()
            statusText = error.localizedDescription
            detailText = bootstrapFailureDetailText
        }
    }

    private func refreshWhisperAvailability() {
        installedWhisperModels = transcriptionService.installedModels()

        if installedWhisperModels.contains(settings.whisperModel) {
            whisperStatusText = L10n.format(
                "app.whisper.model_ready",
                settings.whisperModel.title,
                settings.whisperModel.approximateSize
            )

            isCaptureReady = true
            hasBlockingSetupFailure = false

            if phase != .recording, phase != .processing {
                phase = .idle
                statusText = idleStatusText
                detailText = idleDetailText
            }
        } else {
            whisperStatusText = L10n.format(
                "app.whisper.model_missing",
                settings.whisperModel.title,
                settings.whisperModel.approximateSize
            )

            isCaptureReady = false
            hasBlockingSetupFailure = true

            if phase != .recording, phase != .processing {
                phase = .error
                statusText = L10n.format("app.whisper.not_ready", settings.whisperModel.title)
                detailText = L10n.tr("app.whisper.choose_and_download")
            }
        }
    }

    private func fixLastSavedNoteIfNeeded() async {
        guard let originalNoteURL = lastSavedNoteURL else {
            llmStatusText = L10n.tr("app.llm.no_saved_note")
            return
        }

        cancelPendingSuccessReset()
        await refreshLLMAvailability()

        do {
            let rawText = try String(contentsOf: originalNoteURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else {
                restoreCaptureStateAfterManualLLMAction()
                llmStatusText = L10n.tr("app.llm.no_saved_note")
                return
            }

            isPreparingLLM = true
            phase = .processing
            statusText = L10n.tr("app.status.fixing_text")
            detailText = originalNoteURL.lastPathComponent

            let fixedContent = try await llmPostProcessingService.postProcess(
                transcription: rawText,
                progress: { [weak self] summary, detail in
                    self?.llmStatusText = summary
                    self?.statusText = summary
                    if let detail {
                        self?.detailText = detail
                    }
                }
            )

            preparedLLMModel = .cleanupModel
            llmStatusText = L10n.format("app.llm.ready_model", LocalLLMModel.cleanupModel.label)
            statusText = L10n.tr("app.status.saving_fixed_note")
            detailText = originalNoteURL.lastPathComponent

            let fixedNoteURL = try noteExporter.saveFixedNote(content: fixedContent, basedOn: originalNoteURL)

            if settings.copySavedNoteToClipboard {
                copyToClipboard(fixedContent.body)
            }

            lastSavedNoteURL = fixedNoteURL
            phase = .success
            statusText = settings.copySavedNoteToClipboard
                ? L10n.format("app.status.fixed_saved_and_copied", fixedNoteURL.lastPathComponent)
                : L10n.format("app.status.fixed_saved", fixedNoteURL.lastPathComponent)
            detailText = fixedNoteURL.path
            scheduleReturnToIdleAfterSuccess()
        } catch {
            await refreshLLMAvailability()
            restoreCaptureStateAfterManualLLMAction()
            llmStatusText = error.localizedDescription
        }

        isPreparingLLM = false
    }

    private func restoreCaptureStateAfterManualLLMAction() {
        if isCaptureReady {
            phase = .idle
            statusText = idleStatusText
            detailText = idleDetailText
        } else {
            phase = .error
            statusText = L10n.format("app.whisper.not_ready", settings.whisperModel.title)
            detailText = L10n.tr("app.whisper.choose_and_download")
        }
    }
}
