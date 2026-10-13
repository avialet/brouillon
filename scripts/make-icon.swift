// Genere build/AppIcon.iconset : plaque a la couleur d'accent, initiale du nom en blanc.
// Usage : swift scripts/make-icon.swift [racine]   (puis `make icon` fabrique le .icns)
import AppKit

let accent: UInt32 = 0x8B78E6
let letter = String("Brouillon".prefix(1)).uppercased()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Melange avec le blanc (t > 0) ou le noir (t < 0).
func shade(_ c: NSColor, _ t: CGFloat) -> NSColor {
    let target: CGFloat = t > 0 ? 1 : 0
    let k = abs(t)
    return NSColor(srgbRed: c.redComponent + (target - c.redComponent) * k,
                   green: c.greenComponent + (target - c.greenComponent) * k,
                   blue: c.blueComponent + (target - c.blueComponent) * k, alpha: 1)
}

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let base = color(accent)

    // Plaque (gabarit macOS : 824 px dans 1024, coins 185).
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    base.setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    NSGradient(colors: [shade(base, -0.18), shade(base, 0.16)])!.draw(in: plate, angle: 90)
    // Reflet doux en haut, sans bord : transparent sur la moitie basse, puis lumiere.
    NSGradient(colorsAndLocations: (color(0xFFFFFF, 0), 0), (color(0xFFFFFF, 0), 0.45), (color(0xFFFFFF, 0.2), 1))!
        .draw(in: plate, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Initiale en serif gras, centree optiquement.
    let descriptor = NSFont.systemFont(ofSize: 600 * s, weight: .bold).fontDescriptor.withDesign(.serif)
    let font = descriptor.flatMap { NSFont(descriptor: $0, size: 600 * s) } ?? NSFont.systemFont(ofSize: 600 * s, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let text = NSAttributedString(string: letter, attributes: attributes)
    let bounds = text.boundingRect(with: NSSize(width: 1024 * s, height: 1024 * s), options: [.usesLineFragmentOrigin])
    let origin = NSPoint(x: plate.midX - bounds.width / 2 - bounds.minX,
                         y: plate.midY - bounds.height / 2 - bounds.minY + 10 * s)
    NSGraphicsContext.saveGraphicsState()
    let textShadow = NSShadow()
    textShadow.shadowColor = color(0x000000, 0.18)
    textShadow.shadowBlurRadius = 10 * s
    textShadow.shadowOffset = NSSize(width: 0, height: -6 * s)
    textShadow.set()
    text.draw(with: NSRect(origin: origin, size: bounds.size), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(size: px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
print(iconset.path)
