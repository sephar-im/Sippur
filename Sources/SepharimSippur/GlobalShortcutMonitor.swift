import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalShortcutMonitor {
    struct Shortcut {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let displayName: String

        static let capture = Shortcut(
            keyCode: UInt32(kVK_ANSI_R),
            carbonModifiers: UInt32(cmdKey | shiftKey),
            displayName: "Command-Shift-R"
        )
    }

    static let defaultShortcut = Shortcut.capture
    static let defaultShortcutDisplayName = defaultShortcut.displayName

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }

        let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
        var eventHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )

        guard status == noErr else { return noErr }
        guard eventHotKeyID.signature == monitor.hotKeyID.signature, eventHotKeyID.id == monitor.hotKeyID.id else {
            return noErr
        }

        Task { @MainActor in
            monitor.action()
        }

        return noErr
    }

    private let shortcut: Shortcut
    private let action: @MainActor () -> Void
    private let hotKeyID: EventHotKeyID
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var isStarted = false

    init(
        shortcut: Shortcut = .capture,
        action: @escaping @MainActor () -> Void
    ) {
        self.shortcut = shortcut
        self.action = action
        self.hotKeyID = EventHotKeyID(signature: Self.fourCharCode("SSHT"), id: 1)
    }

    func startIfNeeded() {
        guard !isStarted else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            print("Failed to install global shortcut handler: \(handlerStatus)")
            return
        }

        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }

            print("Failed to register global shortcut: \(hotKeyStatus)")
            return
        }

        isStarted = true
    }

    private static func fourCharCode(_ string: StaticString) -> OSType {
        precondition(string.utf8CodeUnitCount == 4)

        return string.withUTF8Buffer { buffer in
            buffer.reduce(0) { partialResult, codeUnit in
                (partialResult << 8) + OSType(codeUnit)
            }
        }
    }
}
