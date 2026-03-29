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
            return "Idle"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .success:
            return "Success"
        case .error:
            return "Error"
        }
    }

    var accentColor: Color {
        switch self {
        case .idle:
            return Color(red: 0.89, green: 0.20, blue: 0.24)
        case .recording:
            return Color(red: 0.94, green: 0.16, blue: 0.20)
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

enum OutputFormat: String, CaseIterable, Identifiable {
    case txt
    case md

    var id: String { rawValue }

    var label: String {
        rawValue.uppercased()
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case normal
    case obsidian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal:
            return "Normal"
        case .obsidian:
            return "Obsidian"
        }
    }
}

struct ExportSettings: Equatable {
    let folderURL: URL
    let format: OutputFormat
    let mode: OutputMode
}

enum LocalLLMModel: String, Equatable {
    case qwen25_05b = "qwen2.5:0.5b"
    case qwen25_15b = "qwen2.5:1.5b"
}

struct LLMPostProcessingSettings: Equatable {
    let isEnabled: Bool
    let generatesTitle: Bool
    let addsObsidianWikilinks: Bool
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
