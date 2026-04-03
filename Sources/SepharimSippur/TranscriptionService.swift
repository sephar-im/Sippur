@preconcurrency import AVFoundation

import Foundation
import SwiftWhisper

@MainActor
protocol TranscriptionServicing {
    func installedModels() -> Set<WhisperModelChoice>
    func prepare(model: WhisperModelChoice, progress: @escaping @MainActor (String, String?) -> Void) async throws
    func removeModel(_ model: WhisperModelChoice) throws
    func transcribeAudio(
        at audioURL: URL,
        using model: WhisperModelChoice,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String
}

private final class WhisperModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (Int64, Int64) -> Void

    private let progressHandler: ProgressHandler
    private let persistentDownloadURL: URL
    private var continuation: CheckedContinuation<(URLResponse?, URL), Error>?

    init(progressHandler: @escaping ProgressHandler, persistentDownloadURL: URL) {
        self.progressHandler = progressHandler
        self.persistentDownloadURL = persistentDownloadURL
    }

    func download(using session: URLSession, request: URLRequest) async throws -> (URLResponse?, URL) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: persistentDownloadURL.path) {
                try fileManager.removeItem(at: persistentDownloadURL)
            }

            try fileManager.moveItem(at: location, to: persistentDownloadURL)
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            continuation = nil
            session.finishTasksAndInvalidate()
        }

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        guard FileManager.default.fileExists(atPath: persistentDownloadURL.path) else {
            continuation?.resume(throwing: URLError(.badServerResponse))
            return
        }

        continuation?.resume(returning: (task.response, persistentDownloadURL))
    }
}

private final class WhisperProgressDelegate: WhisperDelegate {
    private let progressHandler: @MainActor (Double) -> Void

    init(progressHandler: @escaping @MainActor (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func whisper(_ aWhisper: Whisper, didUpdateProgress progress: Double) {
        let progressHandler = self.progressHandler
        Task { @MainActor in
            progressHandler(progress)
        }
    }
}

@MainActor
final class WhisperTranscriptionService: TranscriptionServicing {
    enum TranscriptionError: LocalizedError {
        case modelNotFound(URL)
        case modelDownloadFailed(String)
        case invalidModelDownload(URL)
        case unreadableAudio
        case unsupportedAudioFormat
        case emptyTranscription
        case whisperFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let modelURL):
                return L10n.format("transcription.error.model_not_found", modelURL.path)
            case .modelDownloadFailed(let message):
                return message
            case .invalidModelDownload(let modelURL):
                return L10n.format("transcription.error.invalid_model_download", modelURL.path)
            case .unreadableAudio:
                return L10n.tr("transcription.error.unreadable_audio")
            case .unsupportedAudioFormat:
                return L10n.tr("transcription.error.unsupported_audio")
            case .emptyTranscription:
                return L10n.tr("transcription.error.empty")
            case .whisperFailed(let message):
                return message
            }
        }
    }

    private let fileManager: FileManager
    private let modelsDirectoryURL: URL
    private var whisper: Whisper?
    private var loadedModel: WhisperModelChoice?
    private var whisperProgressDelegate: WhisperProgressDelegate?

    init(
        fileManager: FileManager = .default,
        modelsDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.modelsDirectoryURL = modelsDirectoryURL ?? Self.defaultModelsDirectoryURL(fileManager: fileManager)
        Self.ensureModelDirectoryExists(fileManager: fileManager, directoryURL: self.modelsDirectoryURL)
    }

    func installedModels() -> Set<WhisperModelChoice> {
        Set(WhisperModelChoice.allCases.filter { hasInstalledModel($0) })
    }

    func prepare(
        model: WhisperModelChoice,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws {
        let modelURL = modelURL(for: model)
        progress(L10n.tr("transcription.progress.checking_local"), modelURL.lastPathComponent)

        if hasInstalledModel(model) {
            progress(L10n.tr("transcription.progress.ready"), modelURL.lastPathComponent)
            return
        }

        progress(L10n.tr("transcription.progress.downloading_model"), L10n.tr("transcription.progress.happens_once"))
        try await downloadModel(model: model, progress: progress)
        progress(L10n.tr("transcription.progress.ready"), modelURL.lastPathComponent)
    }

    func removeModel(_ model: WhisperModelChoice) throws {
        let modelURL = modelURL(for: model)

        if fileManager.fileExists(atPath: modelURL.path) {
            try fileManager.removeItem(at: modelURL)
        }

        if loadedModel == model {
            whisper = nil
            loadedModel = nil
        }
    }

    func transcribeAudio(
        at audioURL: URL,
        using model: WhisperModelChoice,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String {
        let whisper = try loadWhisper(for: model, progress: progress)
        let audioFrames = try loadAudioFrames(from: audioURL)
        let transcription: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            whisper.transcribe(audioFrames: audioFrames) { result in
                switch result {
                case .success(let segments):
                    let transcription = segments
                        .map(\.text)
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if transcription.isEmpty {
                        continuation.resume(throwing: TranscriptionError.emptyTranscription)
                    } else {
                        continuation.resume(returning: transcription)
                    }
                case .failure(let error):
                    continuation.resume(throwing: TranscriptionError.whisperFailed(error.localizedDescription))
                }
            }
        }

        return transcription
    }

    private func loadWhisper(
        for model: WhisperModelChoice,
        progress: @escaping @MainActor (Double) -> Void
    ) throws -> Whisper {
        if let whisper, loadedModel == model {
            let progressDelegate = WhisperProgressDelegate(progressHandler: progress)
            whisper.delegate = progressDelegate
            whisperProgressDelegate = progressDelegate
            return whisper
        }

        let modelURL = modelURL(for: model)
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelNotFound(modelURL)
        }

        let whisper = Whisper(fromFileURL: modelURL, withParams: makeWhisperParams())
        let progressDelegate = WhisperProgressDelegate(progressHandler: progress)
        whisper.delegate = progressDelegate
        self.whisper = whisper
        loadedModel = model
        whisperProgressDelegate = progressDelegate
        return whisper
    }

    private func makeWhisperParams() -> WhisperParams {
        let params = WhisperParams(strategy: .greedy)
        params.language = .auto
        params.translate = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.n_threads = Int32(recommendedThreadCount())
        return params
    }

    private func recommendedThreadCount() -> Int {
        let activeCores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return min(max(activeCores, 4), 8)
    }

    private func hasInstalledModel(_ model: WhisperModelChoice) -> Bool {
        let modelURL = modelURL(for: model)
        guard let attributes = try? fileManager.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }

        return size.int64Value > 0
    }

    private func downloadModel(
        model: WhisperModelChoice,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws {
        let modelURL = modelURL(for: model)
        let temporaryURL = modelURL
            .deletingLastPathComponent()
            .appending(component: "\(modelURL.lastPathComponent).download", directoryHint: .notDirectory)

        try? fileManager.removeItem(at: temporaryURL)

        do {
            let request = URLRequest(url: model.downloadURL)
            let delegate = WhisperModelDownloadDelegate(
                progressHandler: { [weak self] receivedBytes, totalBytes in
                guard let self else { return }

                Task { @MainActor in
                    progress(
                        L10n.tr("transcription.progress.downloading_model"),
                        self.downloadDetail(receivedBytes: receivedBytes, totalBytes: totalBytes)
                    )
                }
                },
                persistentDownloadURL: temporaryURL
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (response, downloadedFileURL) = try await delegate.download(using: session, request: request)
            guard let response else {
                throw TranscriptionError.modelDownloadFailed(L10n.tr("transcription.error.download_unavailable"))
            }
            try validateDownloadResponse(response)

            let downloadedAttributes = try fileManager.attributesOfItem(atPath: downloadedFileURL.path)
            let receivedBytes = (downloadedAttributes[.size] as? NSNumber)?.int64Value ?? 0
            let totalBytes = max(response.expectedContentLength, receivedBytes)

            if receivedBytes <= 0 {
                throw TranscriptionError.invalidModelDownload(modelURL)
            }

            if totalBytes > 0, receivedBytes < totalBytes {
                throw TranscriptionError.invalidModelDownload(modelURL)
            }

            if fileManager.fileExists(atPath: modelURL.path) {
                try fileManager.removeItem(at: modelURL)
            }
            try fileManager.moveItem(at: downloadedFileURL, to: modelURL)
            if loadedModel == model {
                whisper = nil
                loadedModel = nil
            }
        } catch let error as TranscriptionError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw TranscriptionError.modelDownloadFailed(L10n.tr("transcription.error.download_failed_connection"))
        }
    }

    private func validateDownloadResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TranscriptionError.modelDownloadFailed(L10n.tr("transcription.error.download_unavailable"))
        }
    }

    private func downloadDetail(receivedBytes: Int64, totalBytes: Int64) -> String? {
        let transferred = formattedByteCount(receivedBytes)

        guard totalBytes > 0 else {
            return L10n.format("transcription.progress.download_detail_unknown", transferred)
        }

        let total = formattedByteCount(totalBytes)
        let percentage = max(0, min((Double(receivedBytes) / Double(totalBytes)) * 100, 100))
        return L10n.format("transcription.progress.download_detail_known", percentage, transferred, total)
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private static func ensureModelDirectoryExists(fileManager: FileManager, directoryURL: URL) {
        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func loadAudioFrames(from audioURL: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat

        guard format.channelCount == 1, abs(format.sampleRate - 16_000) < 0.5 else {
            throw TranscriptionError.unsupportedAudioFormat
        }

        let frameCapacity = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw TranscriptionError.unreadableAudio
        }

        try audioFile.read(into: buffer)

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            throw TranscriptionError.unreadableAudio
        }

        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else {
                throw TranscriptionError.unreadableAudio
            }

            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else {
                throw TranscriptionError.unreadableAudio
            }

            return (0..<frameCount).map { index in
                let sample = channelData[0][index]
                return max(-1.0, min(Float(sample) / Float(Int16.max), 1.0))
            }

        case .pcmFormatInt32:
            guard let channelData = buffer.int32ChannelData else {
                throw TranscriptionError.unreadableAudio
            }

            return (0..<frameCount).map { index in
                let sample = channelData[0][index]
                return max(-1.0, min(Float(sample) / Float(Int32.max), 1.0))
            }

        default:
            throw TranscriptionError.unsupportedAudioFormat
        }
    }

    private func modelURL(for model: WhisperModelChoice) -> URL {
        modelsDirectoryURL.appending(component: model.fileName, directoryHint: .notDirectory)
    }

    private static func defaultModelsDirectoryURL(fileManager: FileManager) -> URL {
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(component: "Library", directoryHint: .isDirectory)
                .appending(component: "Application Support", directoryHint: .isDirectory)

        return appSupportDirectory
            .appending(component: "Sepharim Sippur", directoryHint: .isDirectory)
            .appending(component: "Models", directoryHint: .isDirectory)
    }
}
