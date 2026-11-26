import Foundation
import Security
import Carbon.HIToolbox

/// Tastenkürzel: virtueller Keycode + Carbon-Modifier + Anzeigetext.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let standard = Shortcut(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥S"
    )
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    /// Fest verdrahtetes Fish-Audio-Modell (bezahlt, mit Latenzgarantie).
    static let model = "s2.1-pro"

    private let defaults = UserDefaults.standard

    @Published var apiKey: String { didSet { Keychain.set(apiKey, for: "fish-api-key") } }
    @Published var voiceID: String { didSet { defaults.set(voiceID, forKey: "voiceID") } }
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "hotkeyCode")
            defaults.set(Int(shortcut.modifiers), forKey: "hotkeyMods")
            defaults.set(shortcut.display, forKey: "hotkeyDisplay")
        }
    }

    private init() {
        apiKey = Keychain.get("fish-api-key") ?? ""
        defaults.removeObject(forKey: "model") // Altlast aus der Version mit Free-Modell
        voiceID = defaults.string(forKey: "voiceID") ?? ""
        let s = defaults.double(forKey: "speed")
        speed = s == 0 ? 1.0 : s
        if let display = defaults.string(forKey: "hotkeyDisplay") {
            shortcut = Shortcut(
                keyCode: UInt32(defaults.integer(forKey: "hotkeyCode")),
                modifiers: UInt32(defaults.integer(forKey: "hotkeyMods")),
                display: display
            )
        } else {
            shortcut = .standard
        }
    }
}

/// Minimaler Schlüsselbund-Zugriff (generisches Passwort).
enum Keychain {
    private static let service = "local.vorleser.app"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
