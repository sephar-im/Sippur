@preconcurrency import AVFoundation

import Foundation
import SwiftWhisper

@MainActor
protocol TranscriptionServicing {
    func transcribeAudio(at audioURL: URL) async throws -> String
}

@MainActor
final class WhisperTranscriptionService: TranscriptionServicing {
    enum TranscriptionError: LocalizedError {
        case modelNotFound(URL)
        case unreadableAudio
        case unsupportedAudioFormat
        case emptyTranscription
        case whisperFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let modelURL):
                return "Whisper model not found. Download ggml-base.bin and place it at \(modelURL.path)."
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
    private var whisper: Whisper?

    init(
        fileManager: FileManager = .default,
        modelURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.modelURL = modelURL ?? Self.defaultModelURL(fileManager: fileManager)
        Self.ensureModelDirectoryExists(fileManager: fileManager, modelURL: self.modelURL)
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
