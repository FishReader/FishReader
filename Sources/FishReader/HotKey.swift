import AppKit
import Carbon.HIToolbox

/// Systemweiter Shortcut über Carbon (braucht keine Sonderrechte).
@MainActor
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ shortcut: Shortcut) {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x56_4C_53_52) /* "VLSR" */, id: 1)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// NSEvent-Modifier in Carbon-Modifier umrechnen.
    nonisolated static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    nonisolated static func displayString(for event: NSEvent) -> String {
        let f = event.modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return s + name }
        return s + (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
