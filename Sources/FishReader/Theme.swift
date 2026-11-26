import SwiftUI
import AppKit

/// Farben und Bausteine im Stil von fish.audio (helles Warmweiß, dunkle Pills, warme Grautöne).
enum Fish {
    static let bg = dynamic(light: 0xFAF8F5, dark: 0x161616)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1D1D1C)
    static let subtle = dynamic(light: 0xF6F0EC, dark: 0x242321)
    static let ink = dynamic(light: 0x161616, dark: 0xFBFAF9)
    static let inkInverse = dynamic(light: 0xFFFFFF, dark: 0x161616)
    static let muted = dynamic(light: 0x7A6F6B, dark: 0x9F928E)
    /// Noch nicht gespielter Teil der Timeline: nur leicht vom Kartenhintergrund abgesetzt.
    static let progress = dynamic(light: 0xEFE9E5, dark: 0x262626)
    static let border = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(red: 1, green: 0.89, blue: 0.83, alpha: 0.11)
            : NSColor(red: 0.38, green: 0.13, blue: 0, alpha: 0.08)
    })

    static let red = Color(hex: 0xF54B45)
    static let orange = Color(hex: 0xFF8E1D)
    static let green = Color(hex: 0x00B489)
    static let blue = Color(hex: 0x027FFF)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

// MARK: - Karten & Felder

struct FishCard: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Fish.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Fish.border))
    }
}

struct FishField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Fish.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Fish.border))
    }
}

extension View {
    func fishCard(padding: CGFloat = 14) -> some View { modifier(FishCard(padding: padding)) }
    func fishField() -> some View { modifier(FishField()) }
}

/// Kleine Überschrift in Versalien, wie in den Fish-Formularen.
struct FishLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Fish.muted)
    }
}

// MARK: - Buttons

struct FishButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .primary
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .secondary ? Fish.border : .clear))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Fish.inkInverse
        case .secondary: return Fish.ink
        case .danger: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Fish.ink
        case .secondary: return Fish.bg
        case .danger: return Fish.red
        }
    }
}

/// Runder Icon-Knopf ohne Hintergrund-Pill (für Aktualisieren, Auge usw.).
struct FishIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Fish.muted)
            .frame(width: 26, height: 26)
            .background(configuration.isPressed ? Fish.subtle : .clear, in: Circle())
            .contentShape(Circle())
    }
}
