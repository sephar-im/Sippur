import AppKit

@MainActor
protocol ClipboardWriting {
    func write(_ text: String)
}

struct SystemClipboardWriter: ClipboardWriting {
    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
