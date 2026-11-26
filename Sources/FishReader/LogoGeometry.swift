import CoreGraphics

/// Geometrie des App-Logos: vier Balken auf einer Gräte, dazu ein Kopf mit Auge.
/// Alle Abstände sind gleich (Balken–Balken und Balken–Kopf). Koordinaten mit y nach unten.
/// Nur CoreGraphics – wird auch vom Icon-Skript mitkompiliert.
enum LogoGeometry {
    // Grundmaße (vom Referenzbild abgeleitet, auf gleichmäßige Werte normiert)
    static let barWidth: CGFloat = 190
    static let gap: CGFloat = 64
    static let height: CGFloat = 672
    static let spineThickness: CGFloat = 58
    static let headWidth: CGFloat = 575
    static let headCornerRadius: CGFloat = 70
    static let tipRadius: CGFloat = 45
    static let eyeOffset: CGFloat = 213      // Augenmitte ab linker Kopfkante
    static let eyeRadius: CGFloat = 85
    static let barCount = 4

    static var eyeCenter: CGPoint { CGPoint(x: headX + eyeOffset, y: centerY) }

    static var centerY: CGFloat { height / 2 }
    static var headX: CGFloat { CGFloat(barCount) * (barWidth + gap) }
    static var tipX: CGFloat { headX + headWidth }

    /// Ausdehnung des Logos.
    static let bounds = CGRect(x: 0, y: 0, width: CGFloat(barCount) * (barWidth + gap) + headWidth, height: height)
    /// Mit Luft oben/unten, damit die Animation nicht abgeschnitten wird.
    static let animatedBounds = bounds.insetBy(dx: 0, dy: -80)

    /// Kopf ohne Auge (Dreieck mit abgerundeten Ecken).
    static let headSolid: CGPath = {
        let a = CGPoint(x: headX, y: 0)            // oben links
        let b = CGPoint(x: headX, y: height)       // unten links
        let c = CGPoint(x: tipX, y: centerY)       // Spitze
        let p = CGMutablePath()
        p.move(to: CGPoint(x: headX, y: centerY))
        p.addArc(tangent1End: b, tangent2End: c, radius: headCornerRadius)
        p.addArc(tangent1End: c, tangent2End: a, radius: tipRadius)
        p.addArc(tangent1End: a, tangent2End: b, radius: headCornerRadius)
        p.closeSubpath()
        return p
    }()

    /// Kopf mit ausgestanztem Auge in Ruhestellung. Einmal berechnet, dann wiederverwendet.
    static let head: CGPath = headSolid.subtracting(eyePath())

    /// Wie weit sich das Auge im Kopf verschieben darf, ohne den Rand zu berühren.
    static let eyeReach: CGFloat = 34

    /// Das Auge als Kreis; `look` (Länge ≤ 1) verschiebt es in diese Richtung.
    static func eyePath(look: CGVector = .zero) -> CGPath {
        let c = CGPoint(x: eyeCenter.x + look.dx * eyeReach, y: eyeCenter.y + look.dy * eyeReach)
        return CGPath(ellipseIn: CGRect(x: c.x - eyeRadius, y: c.y - eyeRadius,
                                        width: 2 * eyeRadius, height: 2 * eyeRadius), transform: nil)
    }

    /// Gesamtes Logo als ein Pfad (Auge ausgestanzt). `stretch(i)` = Höhenfaktor für Balken i.
    /// Vereinigt alles – teuer, daher nur für Icons/Menüleiste, nicht pro Animations-Frame.
    static func path(stretch: (Int) -> CGFloat = { _ in 1 }) -> CGPath {
        parts(stretch: stretch).dropFirst().reduce(head) { $0.union($1) }
    }

    /// Einzelteile ohne Pfad-Booleans (billig): Kopf, Balken, Gräte.
    /// `solidHead`: Kopf ohne Loch – das Auge zeichnet der Aufrufer selbst darüber (z. B. beweglich).
    static func parts(stretch: (Int) -> CGFloat = { _ in 1 }, solidHead: Bool = false) -> [CGPath] {
        var result: [CGPath] = [solidHead ? headSolid : head]
        for i in 0..<barCount {
            let h = height * stretch(i)
            let r = CGRect(x: CGFloat(i) * (barWidth + gap), y: centerY - h / 2, width: barWidth, height: h)
            result.append(CGPath(roundedRect: r, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        }
        // Gräte: von der Mitte des ersten Balkens bis in den Kopf
        result.append(CGPath(rect: CGRect(x: barWidth / 2, y: centerY - spineThickness / 2,
                                          width: headX + headCornerRadius - barWidth / 2, height: spineThickness),
                             transform: nil))
        return result
    }

    /// Transformation, die `viewBox` mittig in `rect` einpasst. `flipY` für AppKit-Koordinaten (y nach oben).
    static func fit(_ viewBox: CGRect, into rect: CGRect, flipY: Bool = false) -> CGAffineTransform {
        let s = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let tx = rect.midX - viewBox.midX * s
        if flipY {
            return CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: tx, ty: rect.midY + viewBox.midY * s)
        }
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: rect.midY - viewBox.midY * s)
    }
}
