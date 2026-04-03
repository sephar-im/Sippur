import Foundation
import SwiftUI

enum CapturePhase: Equatable {
    case idle
    case recording
    case processing
    case success
    case error

    var title: String {
        switch self {
        case .idle:
            return L10n.tr("phase.idle")
        case .recording:
            return L10n.tr("phase.recording")
        case .processing:
            return L10n.tr("phase.processing")
        case .success:
            return L10n.tr("phase.success")
        case .error:
            return L10n.tr("phase.error")
        }
    }

    var accentColor: Color {
        switch self {
        case .idle:
            return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .recording:
            return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .processing:
            return Color(red: 0.88, green: 0.63, blue: 0.19)
        case .success:
            return Color(red: 0.17, green: 0.66, blue: 0.42)
        case .error:
            return Color(red: 0.82, green: 0.33, blue: 0.20)
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "mic.fill"
        case .recording:
            return "stop.fill"
        case .processing:
            return "hourglass"
        case .success:
            return "checkmark"
        case .error:
            return "exclamationmark"
        }
    }

    var isInteractive: Bool {
        self != .processing
    }

    var shouldPulse: Bool {
        self == .recording
    }

    var shouldSpinRing: Bool {
        self == .processing
    }

    var outerRingTrimRange: ClosedRange<Double> {
        switch self {
        case .processing:
            return 0.16...0.88
        default:
            return 0.0...1.0
        }
    }
}

struct ExportSettings: Equatable {
    let folderURL: URL
}

enum WhisperModelChoice: String, CaseIterable, Identifiable, Hashable {
    case base
    case medium
    case largeV3

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .base:
            return "ggml-base.bin"
        case .medium:
            return "ggml-medium.bin"
        case .largeV3:
            return "ggml-large-v3.bin"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var title: String {
        switch self {
        case .base:
            return L10n.tr("whisper.model.base")
        case .medium:
            return L10n.tr("whisper.model.medium")
        case .largeV3:
            return L10n.tr("whisper.model.large_v3")
        }
    }

    var approximateSize: String {
        switch self {
        case .base:
            return "~142 MB"
        case .medium:
            return "~1.5 GB"
        case .largeV3:
            return "~3.1 GB"
        }
    }

    var displayLabel: String {
        "\(title) (\(approximateSize))"
    }
}

struct NoteContent: Equatable {
    let body: String
    let title: String?

    static func whisperOnly(body: String) -> NoteContent {
        NoteContent(
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            title: nil
        )
    }
}

struct NoteDraft: Equatable {
    let fileName: String
    let contents: String
}
