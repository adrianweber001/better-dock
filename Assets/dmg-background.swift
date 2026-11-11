// Zeichnet den Hintergrund für das DMG-Fenster.
// Aufruf (aus dem Projektordner):  swift Assets/dmg-background.swift
// Erzeugt Assets/dmg-background.png und Assets/dmg-background@2x.png.
//
// Die Positionen müssen zu dmg-settings.py passen:
//   App-Symbol   Mitte (330, 160)
//   Programme    Mitte (330, 338)  – der leuchtende freie Platz im gezeichneten Dock
import AppKit

let width: CGFloat = 660, height: CGFloat = 440

/// Rechteck aus Koordinaten mit Ursprung oben links (wie im Finder-Fenster).
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func text(_ string: String, centerX: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ]
    let measured = (string as NSString).size(withAttributes: attributes)
    (string as NSString).draw(at: NSPoint(x: centerX - measured.width / 2, y: height - top - measured.height),
                              withAttributes: attributes)
}

func draw() {
    // Hintergrund: dunkelblauer Verlauf wie im App-Symbol.
    NSGradient(colors: [NSColor(red: 0.22, green: 0.35, blue: 0.56, alpha: 1),
                        NSColor(red: 0.09, green: 0.13, blue: 0.24, alpha: 1)])?
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Kopf: Bildmarke aus dem Logo (linker Teil) und Schriftzug.
    if let logo = NSImage(contentsOfFile: "Assets/logo.png") {
        let markWidth = logo.size.width * 0.44 // linker Teil des Logos = Bildmarke
        let h: CGFloat = 46, w = h * markWidth / logo.size.height
        logo.draw(in: rect(196, 22, w, h),
                  from: NSRect(x: 0, y: 0, width: markWidth, height: logo.size.height),
                  operation: .sourceOver, fraction: 1)
    }
    text("Better Dock", centerX: 372, top: 24, size: 32, weight: .bold, color: .white)
    text("Zieh die App ins Dock, um sie zu installieren", centerX: 330, top: 76, size: 13,
         weight: .medium, color: NSColor(white: 1, alpha: 0.72))

    // Unterlage für die Beschriftungen, damit sie im hellen und dunklen Modus lesbar sind.
    NSColor(red: 0.42, green: 0.48, blue: 0.58, alpha: 0.9).setFill()
    rounded(rect(270, 213, 120, 20), 10).fill()

    // Pfeil vom App-Symbol ins Dock.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 330, y: height - 242))
    arrow.line(to: NSPoint(x: 330, y: height - 268))
    arrow.move(to: NSPoint(x: 318, y: height - 257))
    arrow.line(to: NSPoint(x: 330, y: height - 270))
    arrow.line(to: NSPoint(x: 342, y: height - 257))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(white: 1, alpha: 0.85).setStroke()
    arrow.stroke()

    // Das gezeichnete Dock.
    let dock = rect(92, 284, 476, 134)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    NSColor(white: 1, alpha: 0.13).setFill()
    rounded(dock, 34).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 1, alpha: 0.30).setStroke()
    let border = rounded(dock.insetBy(dx: 0.75, dy: 0.75), 34)
    border.lineWidth = 1.5
    border.stroke()

    // Angedeutete Apps links und rechts.
    let tints: [NSColor] = [
        NSColor(red: 0.45, green: 0.62, blue: 0.86, alpha: 1), NSColor(red: 0.36, green: 0.50, blue: 0.74, alpha: 1),
        NSColor(red: 0.36, green: 0.50, blue: 0.74, alpha: 1), NSColor(red: 0.45, green: 0.62, blue: 0.86, alpha: 1),
    ]
    for (index, x) in [146.0, 230.0, 430.0, 514.0].enumerated() {
        let tile = rect(CGFloat(x) - 32, 300, 64, 64)
        NSGradient(starting: tints[index].withAlphaComponent(0.75), ending: tints[index].withAlphaComponent(0.4))?
            .draw(in: rounded(tile, 15), angle: -90)
        NSColor(white: 1, alpha: 0.55).setFill()
        rounded(NSRect(x: tile.midX - 9, y: tile.midY - 9, width: 18, height: 18), 5).fill()
    }

    // Der freie, leuchtende Platz in der Mitte – hier liegt die Programme-Verknüpfung.
    let slot = rect(330 - 56, 286, 112, 102)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(red: 0.45, green: 0.70, blue: 1, alpha: 0.9)
    glow.shadowBlurRadius = 22
    glow.set()
    NSColor(red: 0.45, green: 0.70, blue: 1, alpha: 0.22).setFill()
    rounded(slot, 24).fill()
    NSGraphicsContext.restoreGraphicsState()
    let dashed = rounded(slot, 24)
    dashed.lineWidth = 2
    dashed.setLineDash([7, 5], count: 2, phase: 0)
    NSColor(red: 0.72, green: 0.86, blue: 1, alpha: 0.95).setStroke()
    dashed.stroke()

    NSColor(red: 0.42, green: 0.48, blue: 0.58, alpha: 0.9).setFill()
    rounded(rect(270, 393, 120, 20), 10).fill()
}

for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // Punkte; die Pixelzahl ergibt die Auflösung
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "Assets/dmg-background.png" : "Assets/dmg-background@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
    print("geschrieben:", name)
}
