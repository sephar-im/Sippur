import Carbon.HIToolbox
import AppKit
import Foundation

@MainActor
final class GlobalShortcutMonitor {
    struct Shortcut: Equatable {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let displayName: String
    }

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

    private let action: @MainActor () -> Void
    private let hotKeyID: EventHotKeyID
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false
    private var shortcut: Shortcut?

    init(
        action: @escaping @MainActor () -> Void
    ) {
        self.action = action
        self.hotKeyID = EventHotKeyID(signature: Self.fourCharCode("SSHT"), id: 1)
    }

    func startIfNeeded() {
        guard !isHandlerInstalled else {
            registerShortcutIfPossible()
            return
        }

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

        isHandlerInstalled = true
        registerShortcutIfPossible()
    }

    func updateShortcut(_ shortcut: Shortcut?) {
        self.shortcut = shortcut
        startIfNeeded()
    }

    func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func registerShortcutIfPossible() {
        unregisterShortcut()

        guard let shortcut else { return }

        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            self.hotKeyRef = nil
            print("Failed to register global shortcut: \(hotKeyStatus)")
            return
        }
    }

    private static func fourCharCode(_ string: StaticString) -> OSType {
        precondition(string.utf8CodeUnitCount == 4)

        return string.withUTF8Buffer { buffer in
            buffer.reduce(0) { partialResult, codeUnit in
                (partialResult << 8) + OSType(codeUnit)
            }
        }
    }

    static func shortcut(from event: NSEvent) -> Shortcut? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else { return nil }

        let keyCode = UInt32(event.keyCode)
        let keyLabel = keyDisplay(for: event)
        guard !keyLabel.isEmpty else { return nil }

        let modifierLabel = displayName(for: modifiers)
        return Shortcut(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers(for: modifiers),
            displayName: "\(modifierLabel)-\(keyLabel)"
        )
    }

    private static func keyDisplay(for event: NSEvent) -> String {
        if let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !characters.isEmpty {
            return characters
        }

        switch Int(event.keyCode) {
        case kVK_Space:
            return L10n.tr("global_shortcut.key.space")
        case kVK_Return:
            return L10n.tr("global_shortcut.key.return")
        case kVK_Delete:
            return L10n.tr("global_shortcut.key.delete")
        case kVK_Escape:
            return L10n.tr("global_shortcut.key.escape")
        default:
            return ""
        }
    }

    private static func displayName(for modifiers: NSEvent.ModifierFlags) -> String {
        var labels: [String] = []

        if modifiers.contains(.command) {
            labels.append(L10n.tr("global_shortcut.mod.command"))
        }
        if modifiers.contains(.shift) {
            labels.append(L10n.tr("global_shortcut.mod.shift"))
        }
        if modifiers.contains(.option) {
            labels.append(L10n.tr("global_shortcut.mod.option"))
        }
        if modifiers.contains(.control) {
            labels.append(L10n.tr("global_shortcut.mod.control"))
        }

        return labels.joined(separator: "-")
    }

    private static func carbonModifiers(for modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0

        if modifiers.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }
        if modifiers.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }
        if modifiers.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }

        return carbonFlags
    }
}
