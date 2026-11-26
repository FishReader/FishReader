import SwiftUI
import AppKit

/// App-Logo; beim Vorlesen pulsieren die Balken mit dem Audiopegel.
/// Mit `lookAt` (Punkt in lokalen Koordinaten) wandert das Auge im Kopf in diese Richtung.
struct AppLogo: View {
    var level: Float = 0
    var active = false
    /// Reserviert Platz oben/unten für die Animation.
    var animated = false
    var lookAt: CGPoint? = nil
    /// Farbe des Auges – muss dem Hintergrund entsprechen, damit es wie ein Loch wirkt.
    var eyeColor: Color = Fish.card

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let box = animated ? LogoGeometry.animatedBounds : LogoGeometry.bounds
                let transform = LogoGeometry.fit(box, into: CGRect(origin: .zero, size: size))
                let look = eyeVector(transform: transform)
                // Mit beweglichem Auge: Kopf voll zeichnen und das Auge in Hintergrundfarbe darüber
                // (billiger als das Loch pro Frame neu auszustanzen).
                let parts = LogoGeometry.parts(stretch: { i in
                    guard active else { return 1 }
                    let wobble = 0.55 + 0.45 * sin(t * 7.5 + Double(i) * 1.3)
                    return 1 + CGFloat(level) * 0.22 * CGFloat(wobble)
                }, solidHead: look != nil)
                let color = GraphicsContext.Shading.color(Fish.ink)
                for part in parts {
                    g.fill(Path(part).applying(transform), with: color)
                }
                if let look {
                    g.fill(Path(LogoGeometry.eyePath(look: look)).applying(transform), with: .color(eyeColor))
                }
            }
        }
    }

    /// Richtung vom Auge zur Maus; je näher die Maus, desto weniger weit wandert das Auge.
    private func eyeVector(transform: CGAffineTransform) -> CGVector? {
        guard let lookAt else { return nil }
        let eye = LogoGeometry.eyeCenter.applying(transform)
        let dx = lookAt.x - eye.x, dy = lookAt.y - eye.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > 0.5 else { return CGVector(dx: 0, dy: 0) }
        let reach = min(1, dist / 70)
        return CGVector(dx: dx / dist * reach, dy: dy / dist * reach)
    }

    /// Monochromes Template-Bild für die Menüleiste.
    static func menuBarImage(height: CGFloat = 14) -> NSImage {
        let box = LogoGeometry.bounds
        let size = NSSize(width: (height * box.width / box.height).rounded(), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var transform = LogoGeometry.fit(box, into: rect)
            if let path = LogoGeometry.path().copy(using: &transform) {
                ctx.addPath(path)
                ctx.setFillColor(.black)
                ctx.fillPath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Mausposition systemweit verfolgen

@MainActor
final class MouseState: ObservableObject {
    @Published var point: CGPoint?
}

/// Unsichtbare Ebene, die die Mausposition (auch außerhalb des Fensters) in ihre lokalen
/// Koordinaten umrechnet – oben links = (0, 0), wie in SwiftUI.
struct MouseTracker: NSViewRepresentable {
    let state: MouseState

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = { p in state.point = p }
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {}

    final class TrackerView: NSView {
        var onMove: ((CGPoint) -> Void)?
        private var timer: Timer?
        private var last: CGPoint?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // Klicks durchlassen

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            let t = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            poll()
        }

        private func poll() {
            guard let window, window.isVisible, window.occlusionState.contains(.visible) else { return }
            let p = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            guard p != last else { return }
            last = p
            onMove?(p)
        }
    }
}
