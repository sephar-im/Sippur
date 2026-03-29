@preconcurrency import AVFoundation

import Foundation

@MainActor
protocol RecordingServicing: AnyObject {
    var unexpectedFailureHandler: (@MainActor (Error) -> Void)? { get set }
    func requestPermission() async -> Bool
    func startRecording() throws -> URL
    func stopRecording() async throws -> URL
}

@MainActor
final class RecordingService: NSObject, RecordingServicing, @preconcurrency AVAudioRecorderDelegate {
    enum RecordingError: LocalizedError {
        case alreadyRecording
        case stopAlreadyInProgress
        case notRecording
        case couldNotStart
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return L10n.tr("recording.error.already_recording")
            case .stopAlreadyInProgress:
                return L10n.tr("recording.error.stop_already_in_progress")
            case .notRecording:
                return L10n.tr("recording.error.not_recording")
            case .couldNotStart:
                return L10n.tr("recording.error.could_not_start")
            case .finalizeFailed:
                return L10n.tr("recording.error.finalize_failed")
            }
        }
    }

    var unexpectedFailureHandler: (@MainActor (Error) -> Void)?

    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() throws -> URL {
        guard recorder == nil, stopContinuation == nil else {
            throw RecordingError.alreadyRecording
        }

        let recordingURL = makeTemporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()

            guard recorder.record() else {
                cleanupCurrentRecording(removeFile: true)
                throw RecordingError.couldNotStart
            }

            self.recorder = recorder
            currentRecordingURL = recordingURL
            return recordingURL
        } catch {
            cleanupCurrentRecording(removeFile: true)
            throw error
        }
    }

    func stopRecording() async throws -> URL {
        guard let recorder else {
            throw RecordingError.notRecording
        }

        guard stopContinuation == nil else {
            throw RecordingError.stopAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            recorder.stop()
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag, let recordingURL = currentRecordingURL {
            self.recorder = nil
            currentRecordingURL = nil

            if let stopContinuation {
                self.stopContinuation = nil
                stopContinuation.resume(returning: recordingURL)
            } else {
                unexpectedFailureHandler?(RecordingError.finalizeFailed)
            }
            return
        }

        handleFailure(RecordingError.finalizeFailed)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        handleFailure(error ?? RecordingError.finalizeFailed)
    }

    private func handleFailure(_ error: Error) {
        cleanupCurrentRecording(removeFile: true)

        if let stopContinuation {
            self.stopContinuation = nil
            stopContinuation.resume(throwing: error)
        } else {
            unexpectedFailureHandler?(error)
        }
    }

    private func cleanupCurrentRecording(removeFile: Bool) {
        recorder = nil

        if removeFile, let currentRecordingURL, fileManager.fileExists(atPath: currentRecordingURL.path) {
            try? fileManager.removeItem(at: currentRecordingURL)
        }

        currentRecordingURL = nil
    }

    private func makeTemporaryRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: .now)
        let fileName = "sepharim-sippur-\(timestamp)-\(UUID().uuidString.prefix(8)).wav"
        return fileManager.temporaryDirectory.appending(component: fileName, directoryHint: .notDirectory)
    }
}
