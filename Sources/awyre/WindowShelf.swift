import AppKit
import ApplicationServices

/// Hält minimierte Fenster über einen Dock-Neustart hinweg minimiert.
///
/// Startet das Dock neu, holt macOS alle minimierten Fenster zurück auf den Bildschirm.
/// Better Dock merkt sie sich deshalb vorher und minimiert sie danach wieder – dabei landen sie
/// dort, wo die aktuelle Einstellung es vorsieht (rechts im Dock oder im App-Symbol).
enum WindowShelf {
    private static var pending: [AXUIElement] = []
    private static var timer: DispatchWorkItem?

    private static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var flag: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &flag)
        return (flag as? Bool) == true
    }

    /// Vor dem Dock-Neustart aufrufen.
    static func remember() {
        guard AXIsProcessTrusted() else { return }
        let minimized = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .flatMap(windows(of:))
            .filter(isMinimized)
        pending.append(contentsOf: minimized.filter { window in !pending.contains { CFEqual($0, window) } })
    }

    /// Nach dem Dock-Neustart aufrufen: minimiert die gemerkten Fenster wieder, sobald das Dock
    /// läuft. Mehrere Neustarts kurz hintereinander werden zusammengefasst.
    static func restoreSoon() {
        timer?.cancel()
        guard !pending.isEmpty else { return }
        let work = DispatchWorkItem {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").isEmpty else {
                restoreSoon() // Dock noch nicht wieder da
                return
            }
            let windows = pending
            pending = []
            for window in windows {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
            Log.write("Nach Dock-Neustart \(windows.count) Fenster wieder minimiert")
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// Minimiert alle Fenster einer App (für Skripte und Tests).
    static func minimizeAll(bundleID: String) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            for window in windows(of: app) {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }
}
