import SwiftUI
import AppKit

@main
struct FishReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var speaker = Speaker.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            if speaker.isBusy {
                Image(systemName: "stop.circle.fill")
            } else {
                Image(nsImage: AppLogo.menuBarImage())
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(to: args[i + 1], dark: args.contains("--dark"), timelineOnly: args.contains("--timeline"))
            return
        }
        HotKey.shared.onPress = { Speaker.shared.shortcutPressed() }
        HotKey.shared.register(Settings.shared.shortcut)
        if !SelectionReader.isTrusted { SelectionReader.requestTrust() }
    }

    /// Entwickler-Hilfe: Panel in ein PNG rendern (`FishReader --snapshot out.png [--dark] [--timeline]`).
    /// `--timeline` rendert nur die Zeitleiste bei 42 % Fortschritt.
    private func snapshot(to path: String, dark: Bool, timelineOnly: Bool) {
        let root: AnyView = timelineOnly
            ? AnyView(TimelineBar(progress: 0.42, enabled: true, loading: false) { _ in }
                .frame(width: 300).padding(16).background(Fish.card))
            : AnyView(PanelView())
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 360, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame.size = host.fittingSize
        window.setContentSize(host.fittingSize)
        window.orderFrontRegardless()

        // `--simulate-permission`: Berechtigung fehlt zuerst und wird nach 1 s erteilt.
        let simulate = CommandLine.arguments.contains("--simulate-permission")
        if simulate {
            SelectionReader.trustOverride = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("vorher: Fenster \(window.frame.height), Inhalt \(host.fittingSize.height)")
                SelectionReader.trustOverride = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (simulate ? 3.5 : 1.0)) {
            host.layoutSubtreeIfNeeded()
            if simulate { print("nachher: Fenster \(window.frame.height), Inhalt \(host.fittingSize.height)") }
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
