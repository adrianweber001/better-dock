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
        commit(hidden: true, values: hiddenValues.mapValues { Optional($0) })
    }

    func show() {
        guard isHidden else { return }
        let saved = store.dictionary(forKey: savedKey) as? [String: Bool] ?? [:]
        // War ein Wert vorher nicht gesetzt, wird er wieder entfernt (nil).
        var values: [String: Bool?] = [:]
        for key in hiddenValues.keys { values[key] = .some(saved[key]) }
        commit(hidden: false, values: values)
    }

    private func commit(hidden: Bool, values: [String: Bool?]) {
        store.set(hidden, forKey: hiddenKey)
        isHidden = hidden
        apply(values, attemptsLeft: 3)
    }

    /// Schreibt die Werte und startet das Dock neu. Das Dock überschreibt beim Beenden manchmal
    /// unsere Werte mit seinem eigenen Stand – deshalb nachprüfen und notfalls wiederholen.
    private func apply(_ values: [String: Bool?], attemptsLeft: Int) {
        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFBoolean }, dockDomain)
        }
        CFPreferencesAppSynchronize(dockDomain)
        Self.restartDock()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            CFPreferencesAppSynchronize(dockDomain)
            let ok = values.allSatisfy { key, value in
                (CFPreferencesCopyAppValue(key as CFString, dockDomain) as? Bool) == value
            }
            if !ok {
                Log.write("Dock hat die Einstellung überschrieben – Versuch wird wiederholt (\(attemptsLeft) übrig)")
                if attemptsLeft > 0 { apply(values, attemptsLeft: attemptsLeft - 1) }
            }
        }
    }

    /// macOS startet das Dock nach dem Beenden automatisch neu. Bewusst mit KILL: Beim normalen
    /// Beenden schreibt das Dock seinen eigenen Stand zurück und überschreibt unsere Änderung.
    static func restartDock() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-KILL", "Dock"]
        try? task.run()
    }
}
