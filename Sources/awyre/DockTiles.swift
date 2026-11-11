import Foundation

/// Liest und schreibt die linke Dock-Belegung (`persistent-apps`).
enum DockTiles {
    typealias Tile = [String: Any]
    private static let domain = "com.apple.dock" as CFString
    private static let key = "persistent-apps" as CFString

    static func read() -> [Tile] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [Tile] ?? []
    }

    static func write(_ tiles: [Tile]) {
        CFPreferencesSetAppValue(key, tiles as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    /// Schreibt die Belegung und startet das Dock neu. Hat das Dock gerade eigene, noch nicht
    /// gespeicherte Änderungen (z. B. nach dem Verschieben eines Symbols), überschreibt es beim
    /// Beenden unsere Werte – deshalb nachprüfen und notfalls wiederholen.
    static func commit(_ tiles: [Tile], attemptsLeft: Int = 3) {
        write(tiles)
        DockController.restartDock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let wanted = tiles.compactMap(path(of:))
            if read().compactMap(path(of:)) != wanted, attemptsLeft > 0 {
                commit(tiles, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    /// Dateipfad der App, auf die eine Kachel zeigt.
    static func path(of tile: Tile) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return nil }
        if let url = URL(string: string), url.isFileURL { return url.standardizedFileURL.path }
        return (string as NSString).standardizingPath
    }

    static func makeTile(appPath: String, label: String) -> Tile {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": [
                    "_CFURLString": URL(fileURLWithPath: appPath, isDirectory: true).absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-label": label,
                "file-type": 41,
            ] as [String: Any],
        ]
    }

    static func encode(_ tile: Tile) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: tile, format: .binary, options: 0)
    }

    static func decode(_ data: Data) -> Tile? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? Tile
    }

    /// Sichert die ursprüngliche Dock-Belegung einmalig, bevor awyre sie verändert.
    static func backupIfNeeded(to url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try? PropertyListSerialization.data(fromPropertyList: read(), format: .xml, options: 0)
        try? data?.write(to: url)
    }
}
