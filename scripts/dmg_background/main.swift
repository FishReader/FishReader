// Zeichnet das Hintergrundbild für das DMG-Fenster (660 × 400 pt, @1x und @2x).
// Layout passt zu den Icon-Positionen in make_dmg.sh: App bei x 170, Programme bei x 490, y 200.
import AppKit

let outDir = CommandLine.arguments[1]
let size = CGSize(width: 660, height: 400)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size   // Punktgröße: der Kontext skaliert dadurch selbst auf @2x (nicht zusätzlich skalieren!)
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    // Heller, warmer Hintergrund (Finder beschriftet Icons auf Hintergrundbildern immer dunkel)
    ctx.setFillColor(CGColor(srgbRed: 0.980, green: 0.973, blue: 0.961, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))

    // Pfeil zwischen App (x 170) und Programme-Ordner (x 490), auf Icon-Höhe (y 200 von oben)
    let y = size.height - 200
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 262, y: y))
    arrow.addLine(to: CGPoint(x: 392, y: y))
    arrow.move(to: CGPoint(x: 380, y: y + 12))
    arrow.addLine(to: CGPoint(x: 394, y: y))
    arrow.addLine(to: CGPoint(x: 380, y: y - 12))
    ctx.addPath(arrow)
    ctx.setStrokeColor(CGColor(srgbRed: 0.71, green: 0.68, blue: 0.66, alpha: 1))
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: URL(fileURLWithPath: outDir + "/background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: outDir + "/background@2x.png"))
