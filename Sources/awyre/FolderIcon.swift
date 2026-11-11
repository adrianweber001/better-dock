import AppKit

/// Zeichnet das Ordner-Symbol: abgerundetes Feld mit Mini-Icons der Apps.
enum FolderIcon {
    static func png(appPaths: [String], pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let s = CGFloat(pixels) / 1024 // alles in 1024er-Koordinaten gedacht
        let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = NSBezierPath(roundedRect: plate, xRadius: 186 * s, yRadius: 186 * s)
        NSGradient(starting: NSColor(white: 0.78, alpha: 0.62), ending: NSColor(white: 0.52, alpha: 0.62))?
            .draw(in: shape, angle: -90)
        NSColor(white: 1, alpha: 0.35).setStroke()
        shape.lineWidth = 6 * s
        shape.stroke()

        let grid = appPaths.count <= 4 ? 2 : 3
        let padding: CGFloat = grid == 2 ? 110 : 84
        let gap: CGFloat = grid == 2 ? 56 : 36
        let cell = (824 - 2 * padding - CGFloat(grid - 1) * gap) / CGFloat(grid)
        for (index, path) in appPaths.prefix(grid * grid).enumerated() {
            let column = CGFloat(index % grid), row = CGFloat(index / grid)
            let x = 100 + padding + column * (cell + gap)
            let y = 100 + 824 - padding - cell - row * (cell + gap) // oben links beginnen
            NSWorkspace.shared.icon(forFile: path)
                .draw(in: NSRect(x: x * s, y: y * s, width: cell * s, height: cell * s))
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Schreibt eine .icns-Datei über das mitgelieferte `iconutil`.
    static func writeICNS(appPaths: [String], to destination: URL) throws {
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                               ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                               ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
            try png(appPaths: appPaths, pixels: pixels)?
                .write(to: iconset.appendingPathComponent("icon_\(name).png"))
        }
        try Shell.run("/usr/bin/iconutil", "-c", "icns", iconset.path, "-o", destination.path)
    }
}

enum Shell {
    struct Failure: Error { let tool: String, status: Int32 }

    static func run(_ tool: String, _ arguments: String...) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 { throw Failure(tool: tool, status: task.terminationStatus) }
    }
}
