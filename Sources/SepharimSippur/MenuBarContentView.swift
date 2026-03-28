import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sepharim Sippur")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Button("Show Capture Window") {
                openWindow(id: "capture")
            }

            Text("State: \(model.phase.title)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Output Folder")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Button("Choose Output Folder…") {
                    settings.chooseOutputFolder()
                }

                Button("Open Output Folder") {
                    settings.openOutputFolder()
                }

                Text(settings.outputFolderPath)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Picker("Format", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Picker("Mode", selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if model.lastRecordingURL != nil {
                Button("Reveal Last Recording") {
                    model.revealLastRecording()
                }
            }

            if model.lastSavedNoteURL != nil {
                Button("Reveal Last Saved Note") {
                    model.revealLastSavedNote()
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
