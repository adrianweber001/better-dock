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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
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
        keepDockVisible()
        WindowShelf.remember() // minimierte Fenster würden sonst auf den Bildschirm zurückspringen
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-KILL", "Dock"]
        try? task.run()
        WindowShelf.restoreSoon()
    }

    // MARK: - Dock sichtbar halten
    //
    // Blendet sich das Dock automatisch aus, wäre es nach dem Neustart weg. Deshalb startet es
    // kurz ohne automatisches Ausblenden und bekommt die Einstellung zurück, sobald die Maus
    // das Dock verlässt.

    private static let pendingKey = "restoreAutohide"
    private static var restoreTimer: Timer?
    private static var restartedAt = Date()

    private static func setAutoHide(_ on: Bool) {
        typealias Setter = @convention(c) (UInt8) -> Void
        let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
        if let symbol = dlsym(handle, "CoreDockSetAutoHideEnabled") {
            unsafeBitCast(symbol, to: Setter.self)(on ? 1 : 0) // wirkt sofort, ohne Neustart
        }
        let domain = "com.apple.dock" as CFString
        CFPreferencesSetAppValue("autohide" as CFString, on as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func keepDockVisible() {
        let domain = "com.apple.dock" as CFString
        let autohide = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool ?? false
        guard autohide || UserDefaults.standard.bool(forKey: pendingKey) else { return }
        UserDefaults.standard.set(true, forKey: pendingKey)
        CFPreferencesSetAppValue("autohide" as CFString, false as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)

        restartedAt = Date()
        restoreTimer?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(restartedAt)
            guard elapsed > 2 else { return }
            if !mouseIsNearDock() || elapsed > 12 { restoreAutoHideIfNeeded() }
        }
        RunLoop.main.add(timer, forMode: .common)
        restoreTimer = timer
    }

    /// Schaltet das automatische Ausblenden wieder ein (auch beim App-Start, falls etwas offen blieb).
    static func restoreAutoHideIfNeeded() {
        restoreTimer?.invalidate()
        restoreTimer = nil
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return }
        UserDefaults.standard.set(false, forKey: pendingKey)
        setAutoHide(true)
    }

    private static func mouseIsNearDock() -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let frame = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.frame else {
            return false
        }
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom" {
        case "left": return mouse.x - frame.minX < 130
        case "right": return frame.maxX - mouse.x < 130
        default: return mouse.y - frame.minY < 130
        }
    }
}
