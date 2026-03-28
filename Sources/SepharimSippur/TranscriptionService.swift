@preconcurrency import AVFoundation

import Foundation
import SwiftWhisper

@MainActor
protocol TranscriptionServicing {
    func prepare(progress: @escaping @MainActor (String, String?) -> Void) async throws
    func transcribeAudio(at audioURL: URL) async throws -> String
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
                return "Whisper model not found at \(modelURL.path). Retry setup to install it."
            case .modelDownloadFailed(let message):
                return message
            case .invalidModelDownload(let modelURL):
                return "The Whisper model download was incomplete. Retry setup to install a fresh copy at \(modelURL.path)."
            case .unreadableAudio:
                return "The recorded audio could not be read for transcription."
            case .unsupportedAudioFormat:
                return "The recorded audio must be 16kHz mono PCM for Whisper transcription."
            case .emptyTranscription:
                return "Whisper finished, but no transcription text was produced."
            case .whisperFailed(let message):
                return message
            }
        }
    }

    private let fileManager: FileManager
    private let modelURL: URL
    private let modelDownloadURL: URL
    private let urlSession: URLSession
    private var whisper: Whisper?

    init(
        fileManager: FileManager = .default,
        modelURL: URL? = nil,
        modelDownloadURL: URL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
        urlSession: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.modelURL = modelURL ?? Self.defaultModelURL(fileManager: fileManager)
        self.modelDownloadURL = modelDownloadURL
        self.urlSession = urlSession
        Self.ensureModelDirectoryExists(fileManager: fileManager, modelURL: self.modelURL)
    }

    func prepare(progress: @escaping @MainActor (String, String?) -> Void) async throws {
        progress("Checking local transcription.", modelURL.lastPathComponent)

        if hasInstalledModel() {
            progress("Local transcription ready.", modelURL.lastPathComponent)
            return
        }

        progress("Downloading Whisper model.", "This happens once.")
        try await downloadModel(progress: progress)
        progress("Local transcription ready.", modelURL.lastPathComponent)
    }

    func transcribeAudio(at audioURL: URL) async throws -> String {
        let whisper = try loadWhisper()
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

    private func loadWhisper() throws -> Whisper {
        if let whisper {
            return whisper
        }

        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelNotFound(modelURL)
        }

        let whisper = Whisper(fromFileURL: modelURL)
        self.whisper = whisper
        return whisper
    }

    private func hasInstalledModel() -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }

        return size.int64Value > 0
    }

    private func downloadModel(
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws {
        let temporaryURL = modelURL
            .deletingLastPathComponent()
            .appending(component: "\(modelURL.lastPathComponent).download", directoryHint: .notDirectory)

        try? fileManager.removeItem(at: temporaryURL)
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)

        do {
            let (bytes, response) = try await urlSession.bytes(from: modelDownloadURL)
            try validateDownloadResponse(response)

            guard let fileHandle = try? FileHandle(forWritingTo: temporaryURL) else {
                throw TranscriptionError.modelDownloadFailed("The Whisper model could not be saved locally. Check disk space and retry setup.")
            }

            defer {
                try? fileHandle.close()
            }

            let totalBytes = max(response.expectedContentLength, 0)
            var receivedBytes: Int64 = 0
            var buffer = Data()
            buffer.reserveCapacity(64 * 1024)

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try fileHandle.write(contentsOf: buffer)
                    receivedBytes += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    progress("Downloading Whisper model.", downloadDetail(receivedBytes: receivedBytes, totalBytes: totalBytes))
                }
            }

            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
                receivedBytes += Int64(buffer.count)
                progress("Downloading Whisper model.", downloadDetail(receivedBytes: receivedBytes, totalBytes: totalBytes))
            }

            if receivedBytes <= 0 {
                throw TranscriptionError.invalidModelDownload(modelURL)
            }

            if totalBytes > 0, receivedBytes < totalBytes {
                throw TranscriptionError.invalidModelDownload(modelURL)
            }

            if fileManager.fileExists(atPath: modelURL.path) {
                try fileManager.removeItem(at: modelURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: modelURL)
            whisper = nil
        } catch let error as TranscriptionError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw TranscriptionError.modelDownloadFailed("Whisper setup failed while downloading the local model. Check your connection and retry setup.")
        }
    }

    private func validateDownloadResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TranscriptionError.modelDownloadFailed("Whisper setup failed because the model download endpoint was unavailable.")
        }
    }

    private func downloadDetail(receivedBytes: Int64, totalBytes: Int64) -> String? {
        guard totalBytes > 0 else {
            return "Preparing local model."
        }

        let percentage = Int((Double(receivedBytes) / Double(totalBytes)) * 100)
        return "\(max(0, min(percentage, 100)))%"
    }

    private static func ensureModelDirectoryExists(fileManager: FileManager, modelURL: URL) {
        try? fileManager.createDirectory(
            at: modelURL.deletingLastPathComponent(),
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

    private static func defaultModelURL(fileManager: FileManager) -> URL {
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(component: "Library", directoryHint: .isDirectory)
                .appending(component: "Application Support", directoryHint: .isDirectory)

        return appSupportDirectory
            .appending(component: "Sepharim Sippur", directoryHint: .isDirectory)
            .appending(component: "Models", directoryHint: .isDirectory)
            .appending(component: "ggml-base.bin", directoryHint: .notDirectory)
    }
}
