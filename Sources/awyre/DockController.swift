import AppKit

/// Schaltet die Dock-Einstellungen um, die den rechten Dock-Bereich füllen.
final class DockController: ObservableObject {
    static let shared = DockController()

    @Published private(set) var isHidden: Bool

    private let dockDomain = "com.apple.dock" as CFString
    /// Einstellungen, die im "ausgeblendet"-Zustand erzwungen werden.
    private let hiddenValues: [String: Bool] = [
        "minimize-to-application": true,
        "show-recents": false,
    ]
    private let store = UserDefaults.standard
    private let hiddenKey = "isHidden"
    private let savedKey = "savedDockValues"

    private init() {
        isHidden = store.bool(forKey: hiddenKey)
    }

    func toggle() {
        isHidden ? show() : hide()
    }

    func hide() {
        guard !isHidden else { return }
        // Ausgangswerte merken (nur Schlüssel, die überhaupt gesetzt waren).
        var saved: [String: Bool] = [:]
        for key in hiddenValues.keys {
            if let value = CFPreferencesCopyAppValue(key as CFString, dockDomain) as? Bool {
                saved[key] = value
            }
        }
        store.set(saved, forKey: savedKey)

        for (key, value) in hiddenValues {
            CFPreferencesSetAppValue(key as CFString, value as CFBoolean, dockDomain)
        }
        commit(hidden: true)
    }

    func show() {
        guard isHidden else { return }
        let saved = store.dictionary(forKey: savedKey) as? [String: Bool] ?? [:]
        for key in hiddenValues.keys {
            if let value = saved[key] {
                CFPreferencesSetAppValue(key as CFString, value as CFBoolean, dockDomain)
            } else {
                // War vorher nicht gesetzt -> wieder entfernen.
                CFPreferencesSetAppValue(key as CFString, nil, dockDomain)
            }
        }
        commit(hidden: false)
    }

    private func commit(hidden: Bool) {
        CFPreferencesAppSynchronize(dockDomain)
        store.set(hidden, forKey: hiddenKey)
        isHidden = hidden
        Self.restartDock()
    }

    /// macOS startet das Dock nach dem Beenden automatisch neu.
    static func restartDock() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}
