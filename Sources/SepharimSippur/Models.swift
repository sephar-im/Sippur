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
            return Color(red: 0.52, green: 0.60, blue: 0.68)
        case .recording:
            return Color(red: 0.89, green: 0.24, blue: 0.29)
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
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case txt
    case md

    var id: String { rawValue }

    var label: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        rawValue
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

struct NoteDraft: Equatable {
    let fileName: String
    let contents: String
}
