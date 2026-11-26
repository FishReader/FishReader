// Erzeugt das App-Icon (Logo auf warmweißem Grund) als .iconset-Ordner.
// Wird zusammen mit Sources/FishReader/LogoGeometry.swift kompiliert (siehe build.sh).
import AppKit

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    // Warmweißer Hintergrund
    NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.965, green: 0.941, blue: 0.925, alpha: 1),
    ])!.draw(in: path, angle: -90)
    NSColor(srgbRed: 0.38, green: 0.13, blue: 0, alpha: 0.10).setStroke()
    path.lineWidth = max(1, s * 0.004)
    path.stroke()

    // Logo
    let target = rect.insetBy(dx: rect.width * 0.11, dy: rect.width * 0.11)
    var transform = LogoGeometry.fit(LogoGeometry.bounds, into: target, flipY: true)
    if let logo = LogoGeometry.path().copy(using: &transform) {
        let ctx = gc.cgContext
        ctx.addPath(logo)
        ctx.setFillColor(CGColor(srgbRed: 0.086, green: 0.086, blue: 0.086, alpha: 1))
        ctx.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try render(size * scale).write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
