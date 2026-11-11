import AppKit
import ApplicationServices

/// Ordner per Ziehen: Eine App im Dock auf eine andere ziehen, kurz halten, loslassen.
///
/// Das Dock selbst kennt das nicht. Better Dock beobachtet deshalb die Maus und liest über die
/// Bedienungshilfen-Schnittstelle aus, wo welches Dock-Symbol liegt.
final class DragMerge: ObservableObject {
    static let shared = DragMerge()

    /// So lange muss die App über dem Ziel gehalten werden.
    private let holdTime: TimeInterval = 0.5

    @Published private(set) var enabled: Bool
    private var monitors: [Any] = []

    private struct Item { let path: String; let frame: CGRect }
    private var items: [Item] = []
    private var source: String?
    private var target: String?
    private var armed = false
    private var armTimer: DispatchWorkItem?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "dragMerge")
        if enabled { start() }
    }

    var hasPermission: Bool { AXIsProcessTrusted() }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "dragMerge")
        if on {
            // Zeigt beim ersten Mal den macOS-Dialog für die Bedienungshilfen-Berechtigung.
            let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(prompt)
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard monitors.isEmpty else { return }
        let add = { (mask: NSEvent.EventTypeMask, handler: @escaping () -> Void) in
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) {
                self.monitors.append(monitor)
            }
        }
        add(.leftMouseDown) { [weak self] in self?.mouseDown() }
        add(.leftMouseDragged) { [weak self] in self?.mouseDragged() }
        add(.leftMouseUp) { [weak self] in self?.mouseUp() }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    // MARK: - Mausverlauf

    private func mouseDown() {
        reset()
        guard AXIsProcessTrusted() else { return }
        let point = Self.mousePoint()
        items = Self.dockItems(around: point)
        // Nur Apps lassen sich ziehen, keine Ordner.
        if let hit = items.first(where: { $0.frame.contains(point) }), !Self.isFolder(hit.path) {
            source = hit.path
        }
    }

    private func mouseDragged() {
        guard let source else { return }
        let point = Self.mousePoint()
        // Nur die Mitte des Symbols zählt, damit normales Umsortieren nichts auslöst.
        let hit = items.first {
            $0.path != source && $0.frame.insetBy(dx: $0.frame.width * 0.15, dy: $0.frame.height * 0.15).contains(point)
        }?.path
        guard hit != target else { return }

        target = hit
        armed = false
        armTimer?.cancel()
        guard hit != nil else { return }
        let timer = DispatchWorkItem { [weak self] in
            self?.armed = true
            NSSound(named: "Tink")?.play() // Signal: jetzt loslassen
        }
        armTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime, execute: timer)
    }

    private func mouseUp() {
        defer { reset() }
        guard armed, let source, let target else { return }
        // Dem Dock kurz Zeit geben, sein eigenes Loslassen zu verarbeiten.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            FolderStore.shared.merge(source: source, target: target)
        }
    }

    private func reset() {
        armTimer?.cancel()
        armTimer = nil
        armed = false
        source = nil
        target = nil
        items = []
    }

    // MARK: - Dock auslesen

    static func isFolder(_ path: String) -> Bool {
        path.hasPrefix(FolderBuilder.bundlesDirectory.path + "/")
    }

    /// Mausposition in Bildschirmkoordinaten mit Ursprung oben links (wie die Bedienungshilfen).
    private static func mousePoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: height - location.y)
    }

    /// Alle App-Symbole im Dock mit Position – leer, wenn `point` gar nicht im Dock liegt.
    private static func dockItems(around point: CGPoint) -> [Item] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = children(of: app).first,
              let listFrame = frame(of: list), listFrame.insetBy(dx: -4, dy: -4).contains(point) else { return [] }

        return children(of: list).compactMap { element in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
                  let url = value as? URL ?? (value as? NSURL) as URL?,
                  url.pathExtension == "app",
                  let frame = frame(of: element) else { return nil }
            return Item(path: url.standardizedFileURL.path, frame: frame)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
