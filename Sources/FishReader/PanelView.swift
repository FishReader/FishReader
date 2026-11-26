import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        // Feste Höhe: nichts blendet sich ein oder aus, damit das Menüleisten-Fenster nie die Größe ändern muss.
        VStack(spacing: 12) {
            header
            PlayerCard()
            HStack(spacing: 12) {
                CreditsCard()
                LogoCard()
            }
            .frame(height: 96)
            settingsCard
        }
        .padding(16)
        .frame(width: 360)
        .background(Fish.bg)
        .tint(Fish.ink)
        .onAppear { Balance.shared.refresh() }
        .onChange(of: settings.apiKey) { _, _ in Balance.shared.refreshSoon() }
    }

    // MARK: Kopfzeile

    private var header: some View {
        HStack {
            Text("FishReader")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Fish.ink)
            Spacer()
            HStack(spacing: 6) {
                Text(verbatim: "S2.1 Pro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Fish.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Fish.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Fish.border))
                QuitButton()
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Einstellungen

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                FishLabel("API key")
                HStack(spacing: 10) {
                    SecureField("Fish Audio API key", text: $settings.apiKey)
                        .fishField()
                    KeyStatusBadge()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FishLabel("Voice")
                TextField("Voice-ID", text: $settings.voiceID)
                    .fishField()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    FishLabel("Speed")
                    Spacer()
                    Text(String(format: "%.2f×", settings.speed))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Fish.ink)
                }
                Slider(value: Binding(
                    get: { settings.speed },
                    set: { settings.speed = ($0 * 20).rounded() / 20 }
                ), in: 0.5...2.0)
                .controlSize(.small)
            }

            HStack {
                FishLabel("Shortcut")
                Spacer()
                ShortcutRecorder(shortcut: $settings.shortcut)
            }
        }
        .fishCard()
    }

}

/// „Quit“-Pill, die beim Hovern rot wird.
struct QuitButton: View {
    @StateObject private var hover = HoverState()

    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            Text("Quit")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover.isHovered ? Fish.red : Fish.muted)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(hover.isHovered ? Fish.red.opacity(0.12) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(hover.isHovered ? Fish.red.opacity(0.6) : Fish.border))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover.isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.isHovered)
        .help("Quit FishReader")
    }
}

@MainActor
final class HoverState: ObservableObject {
    @Published var isHovered = false
}

// MARK: - Player

struct PlayerCard: View {
    @ObservedObject private var speaker = Speaker.shared
    @ObservedObject private var settings = Settings.shared
    @StateObject private var access = AccessState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { speaker.playButtonPressed() } label: {
                    Image(systemName: playIcon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Fish.inkInverse)
                        .frame(width: 44, height: 44)
                        .background(Fish.ink, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help(playHelp)

                TimelineBar(
                    progress: speaker.progress,
                    enabled: speaker.hasTrack,
                    loading: speaker.phase == .loading
                ) { speaker.seek(to: $0) }
            }

            statusLine
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(height: 14)       // immer genau eine Zeile – die Panel-Höhe bleibt konstant
                .padding(.horizontal, 2)
        }
        .fishCard(padding: 16)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            let trusted = SelectionReader.isTrusted
            if trusted != access.trusted { access.trusted = trusted }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if showAccessPrompt {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Fish.orange)
                Text("Accessibility access needed").foregroundStyle(Fish.muted)
                Spacer(minLength: 8)
                Button {
                    SelectionReader.requestTrust()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Grant")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Fish.ink)
                }
                .buttonStyle(.plain)
                .help("Open System Settings › Privacy & Security › Accessibility")
            }
        } else {
            HStack(spacing: 6) {
                if isError {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                Text(statusText)
                    .truncationMode(.tail)
                    .help(statusText)
                Spacer(minLength: 8)
                if speaker.hasTrack {
                    Text("\(Self.time(speaker.position)) / \(Self.time(speaker.duration))")
                        .monospacedDigit()
                        .foregroundStyle(Fish.muted)
                }
            }
            .foregroundStyle(isError ? Fish.red : Fish.muted)
        }
    }

    /// Hinweis nur zeigen, solange nichts läuft – beim Vorlesen hat der Status Vorrang.
    private var showAccessPrompt: Bool {
        guard !access.trusted else { return false }
        switch speaker.phase {
        case .idle, .error: return true
        default: return false
        }
    }

    private var isError: Bool {
        if case .error = speaker.phase { return true }
        return false
    }

    private var playIcon: String {
        switch speaker.phase {
        case .loading: return "stop.fill"
        case .playing: return "pause.fill"
        case .finished: return "arrow.counterclockwise"
        case .idle, .paused, .error: return "play.fill"
        }
    }

    private var playHelp: String {
        switch speaker.phase {
        case .loading: return "Cancel"
        case .playing: return "Pause"
        case .paused: return "Resume"
        case .finished: return "Play again"
        case .idle, .error: return "Read text from the clipboard"
        }
    }

    private var statusText: String {
        switch speaker.phase {
        case .idle: return "Select text and press \(settings.shortcut.display), or ▶ for clipboard"
        case .loading: return "Generating voice…"
        case .playing: return speaker.receiving ? "Streaming…" : "Playing"
        case .paused: return "Paused"
        case .finished: return "Finished"
        case .error(let message): return message
        }
    }

    static func time(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Zeitleiste zum Anzeigen und Spulen (klicken oder ziehen).
struct TimelineBar: View {
    var progress: Double
    var enabled: Bool
    var loading: Bool
    var onSeek: (Double) -> Void
    @StateObject private var scrub = ScrubState()

    var body: some View {
        GeometryReader { geo in
            let shown = scrub.fraction ?? progress
            ZStack(alignment: .leading) {
                // Rest grau, Gespieltes hell – mit gerader Kante, die Kapsel schneidet nur die Enden rund.
                Rectangle().fill(Fish.progress)
                if loading {
                    LoadingSweep(height: geo.size.height)
                } else if shown > 0 {
                    Rectangle()
                        .fill(Fish.ink)
                        .frame(width: geo.size.width * shown)
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled else { return }
                        scrub.fraction = min(max(v.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { v in
                        guard enabled else { return }
                        scrub.fraction = nil
                        onSeek(min(max(v.location.x / geo.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 40)
        .help(enabled ? "Click or drag to seek" : "")
    }
}

/// Grauer Balken, der während der Generierung hin und her läuft.
struct LoadingSweep: View {
    let height: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let w = geo.size.width * 0.3
                let phase = (sin(context.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
                Capsule()
                    .fill(Fish.ink)
                    .frame(width: w, height: height)
                    .offset(x: (geo.size.width - w) * phase)
            }
        }
    }
}

@MainActor
final class ScrubState: ObservableObject {
    @Published var fraction: Double?
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Guthaben & Logo

struct CreditsCard: View {
    @ObservedObject private var balance = Balance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API credits")
                .font(.system(size: 12))
                .foregroundStyle(Fish.muted)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .fishCard(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture { balance.refresh() }
        .help("Click to refresh")
    }

    @ViewBuilder private var content: some View {
        switch balance.state {
        case .loading:
            ProgressView().controlSize(.small).frame(height: 30)
        case .value(let v):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Balance.format(v))
                    .font(.system(size: 26, weight: .medium).monospacedDigit())
                    .foregroundStyle(Fish.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if v < 1 {
                    Text("Low")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Fish.orange)
                }
            }
        case .unknown, .invalidKey, .error:
            Text("—")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Fish.muted)
        }
    }
}

/// Das Logo, dessen Auge der Maus folgt und dessen Balken beim Vorlesen pulsieren.
struct LogoCard: View {
    @ObservedObject private var speaker = Speaker.shared
    @StateObject private var mouse = MouseState()

    var body: some View {
        AppLogo(level: speaker.level, active: speaker.phase == .playing, animated: true, lookAt: mouse.point)
            .background(MouseTracker(state: mouse))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fishCard(padding: 12)
    }
}

/// Kreis neben dem API-Key: Haken = gültig, Kreuz = abgelehnt.
struct KeyStatusBadge: View {
    @ObservedObject private var balance = Balance.shared

    var body: some View {
        ZStack {
            switch balance.state {
            case .unknown:
                Circle().strokeBorder(Fish.border, lineWidth: 1.5)
            case .loading:
                Circle().strokeBorder(Fish.border, lineWidth: 1.5)
                ProgressView().controlSize(.mini)
            case .value:
                Circle().fill(Fish.ink)
                Image(systemName: "checkmark").foregroundStyle(Fish.inkInverse)
            case .invalidKey:
                Circle().fill(Fish.red)
                Image(systemName: "xmark").foregroundStyle(.white)
            case .error:
                Circle().fill(Fish.orange)
                Image(systemName: "exclamationmark").foregroundStyle(.white)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .frame(width: 22, height: 22)
        .help(help)
        .animation(.easeOut(duration: 0.15), value: balance.state)
    }

    private var help: String {
        switch balance.state {
        case .unknown: return "No API key"
        case .loading: return "Checking key…"
        case .value: return "API key valid"
        case .invalidKey: return "API key rejected"
        case .error(let msg): return msg
        }
    }
}

// MARK: - Shortcut

/// Knopf, der die nächste Tastenkombination als Shortcut aufnimmt.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @StateObject private var rec = RecorderState()

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(rec.recording ? "Press keys…" : shortcut.display)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 64)
            }
            .buttonStyle(FishButtonStyle(kind: rec.recording ? .primary : .secondary, height: 28))
            if shortcut != .standard && !rec.recording {
                Button { apply(.standard) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(FishIconButtonStyle())
                    .help("Restore default")
            }
        }
        .onDisappear { finish() }
    }

    private func toggle() {
        if rec.recording { finish(); return }
        rec.recording = true
        HotKey.shared.unregister()
        rec.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { finish(); return nil } // Esc bricht ab
            let mods = HotKey.carbonModifiers(event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil }
            apply(Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods,
                           display: HotKey.displayString(for: event)))
            return nil
        }
    }

    private func apply(_ new: Shortcut) {
        shortcut = new
        finish()
    }

    private func finish() {
        if let m = rec.monitor { NSEvent.removeMonitor(m) }
        rec.monitor = nil
        rec.recording = false
        HotKey.shared.register(shortcut)
    }
}

@MainActor
final class AccessState: ObservableObject {
    @Published var trusted = SelectionReader.isTrusted
}

@MainActor
final class RecorderState: ObservableObject {
    @Published var recording = false
    var monitor: Any?
}
