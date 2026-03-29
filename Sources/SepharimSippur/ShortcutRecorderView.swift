import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    let shortcutDisplayName: String
    let onShortcutChange: (GlobalShortcutMonitor.Shortcut?) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(isRecording ? "Press Shortcut…" : shortcutDisplayName) {
                toggleRecording()
            }
            .buttonStyle(.bordered)

            if isRecording {
                Text("Use Command, Shift, Option, or Control with a key.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                onShortcutChange(nil)
                stopRecording()
                return nil
            }

            guard let shortcut = GlobalShortcutMonitor.shortcut(from: event) else {
                NSSound.beep()
                return nil
            }

            onShortcutChange(shortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
