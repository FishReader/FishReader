import AppKit
import ApplicationServices

/// Liest den aktuell markierten Text der vordersten App.
/// 1. Versuch: Accessibility-API. 2. Versuch: ⌘C simulieren und Zwischenablage wiederherstellen.
@MainActor
enum SelectionReader {
    /// Nur für den Snapshot-Test: erzwingt einen Berechtigungs-Zustand.
    static var trustOverride: Bool?
    static var isTrusted: Bool { trustOverride ?? AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func selectedText() async -> String? {
        if let t = viaAccessibility(), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return await viaCopy()
    }

    private static func viaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func viaCopy() async -> String? {
        let pb = NSPasteboard.general
        // Bisherigen Inhalt sichern
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let before = pb.changeCount

        // Warten, bis die Shortcut-Modifier losgelassen sind, sonst wird aus ⌘C z. B. ⌃⌥⌘C.
        let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != before {
                text = pb.string(forType: .string)
                break
            }
        }

        // Zwischenablage wiederherstellen
        if pb.changeCount != before {
            pb.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
        return text
    }
}
