import Foundation

struct DockFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var appPaths: [String] = []
}

/// Was awyre zuletzt wirklich ins Dock geschrieben hat – nötig, um es exakt rückgängig zu machen.
private struct AppliedFolder: Codable {
    struct RemovedTile: Codable {
        let index: Int
        let path: String
        let plist: Data
    }
    let folderID: UUID
    let bundlePath: String
    let removed: [RemovedTile]
}

final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    @Published var folders: [DockFolder] = []
    @Published var lastError: String?
    private var applied: [AppliedFolder] = []

    private let directory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("awyre", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private var foldersFile: URL { directory.appendingPathComponent("folders.json") }
    private var appliedFile: URL { directory.appendingPathComponent("applied.json") }
    private var backupFile: URL { directory.appendingPathComponent("dock-backup.plist") }

    private init() { load() }

    func load() {
        if let data = try? Data(contentsOf: foldersFile),
           let value = try? JSONDecoder().decode([DockFolder].self, from: data) {
            folders = value
        }
        if let data = try? Data(contentsOf: appliedFile),
           let value = try? JSONDecoder().decode([AppliedFolder].self, from: data) {
            applied = value
        }
    }

    /// Apps, die im Dock liegen oder von awyre in Ordner verschoben wurden.
    var dockAppPaths: [String] {
        let current = DockTiles.read().compactMap(DockTiles.path(of:))
        let folderBundles = Set(applied.map(\.bundlePath))
        let moved = applied.flatMap { $0.removed.map(\.path) }
        var seen = Set<String>()
        return (current.filter { !folderBundles.contains($0) } + moved).filter { seen.insert($0).inserted }
    }

    /// Ziehen im Dock: `source` wurde auf `target` gezogen (App oder bestehender Ordner).
    func merge(source: String, target: String) {
        guard source != target else { return }
        for index in folders.indices { folders[index].appPaths.removeAll { $0 == source } }
        if let id = applied.first(where: { $0.bundlePath == target })?.folderID,
           let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].appPaths.append(source)
        } else if !DragMerge.isFolder(target) {
            for index in folders.indices { folders[index].appPaths.removeAll { $0 == target } }
            folders.append(DockFolder(name: "Ordner", appPaths: [target, source]))
        } else {
            return
        }
        apply()
    }

    /// Eine App wurde aus dem geöffneten Ordner herausgezogen. Bleibt nur noch eine App übrig,
    /// löst sich der Ordner auf (wie am iPad) – alle Apps kehren an ihren Platz im Dock zurück.
    func remove(app: String, fromBundle bundle: String) {
        guard let id = applied.first(where: { $0.bundlePath == bundle })?.folderID,
              let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].appPaths.removeAll { $0 == app }
        if folders[index].appPaths.count < 2 { folders.remove(at: index) }
        apply()
    }

    /// Schreibt die Ordner ins Dock: erst den alten Stand zurücknehmen, dann neu aufbauen.
    func apply() {
        lastError = nil
        do {
            try JSONEncoder().encode(folders).write(to: foldersFile)
            DockTiles.backupIfNeeded(to: backupFile)
            var tiles = DockTiles.read()

            // 1. Bisherige Ordner rückgängig machen (umgekehrte Reihenfolge => exakter Ausgangszustand).
            for old in applied.reversed() {
                tiles.removeAll { DockTiles.path(of: $0) == old.bundlePath }
                for removed in old.removed.sorted(by: { $0.index < $1.index }) {
                    guard let tile = DockTiles.decode(removed.plist),
                          !tiles.contains(where: { DockTiles.path(of: $0) == removed.path }) else { continue }
                    tiles.insert(tile, at: min(removed.index, tiles.count))
                }
            }

            // 2. Aktuelle Ordner aufbauen.
            try FolderBuilder.reset()
            var newApplied: [AppliedFolder] = []
            var usedNames = Set<String>()
            for folder in folders where !folder.appPaths.isEmpty {
                var name = folder.name.replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .trimmingCharacters(in: .whitespaces)
                if name.isEmpty { name = "Ordner" }
                var unique = name, counter = 2
                while !usedNames.insert(unique.lowercased()).inserted { unique = "\(name) \(counter)"; counter += 1 }

                let bundle = try FolderBuilder.build(folder, bundleName: unique)

                let members = Set(folder.appPaths)
                var removed: [AppliedFolder.RemovedTile] = []
                for (index, tile) in tiles.enumerated() {
                    guard let path = DockTiles.path(of: tile), members.contains(path),
                          let plist = DockTiles.encode(tile) else { continue }
                    removed.append(.init(index: index, path: path, plist: plist))
                }
                for item in removed.reversed() { tiles.remove(at: item.index) }
                let position = min(removed.first?.index ?? tiles.count, tiles.count)
                tiles.insert(DockTiles.makeTile(appPath: bundle.path, label: folder.name), at: position)
                newApplied.append(.init(folderID: folder.id, bundlePath: bundle.path, removed: removed))
            }

            applied = newApplied
            try JSONEncoder().encode(applied).write(to: appliedFile)
            DockTiles.commit(tiles)
        } catch {
            lastError = "Ordner konnten nicht übernommen werden: \(error)"
            Log.write(lastError ?? "")
        }
    }
}
