import AppKit
import ApplicationServices

/// Ordner per Ziehen: Eine App im Dock auf eine andere ziehen, kurz halten, loslassen.
///
/// Das Dock selbst kennt das nicht. Better Dock beobachtet deshalb die Maus und liest über die
/// Bedienungshilfen-Schnittstelle aus, wo welches Dock-Symbol liegt.
final class DragMerge: ObservableObject {
    static let shared = DragMerge()

    /// So lange muss die App über dem Ziel gehalten werden.
    private let holdTime: TimeInterval = 0.45

    @Published private(set) var enabled: Bool
    private var monitors: [Any] = []

    struct Item { let path: String; let frame: CGRect }
    private var items: [Item] = []
    private var source: String?
    private var target: String?
    private var armed = false
    private var poll: Timer?
    private var lastTrusted: Bool?
    private var upTicks = 0
    private let doublePressTime: TimeInterval = 0.5
    private var lastDownPath: String?
    private var lastDownTime = Date.distantPast
    private let shakeDistance: CGFloat = 8
    private var shakeDirection: CGFloat = 0
    private var shakeExtreme: CGFloat = 0
    private var shakeTurns: [Date] = []
    private var restPoint = CGPoint.zero
    private var restSince = Date()
    private var overlay: NSWindow?
    private var dragStart = Date()

    private init() {
        // Standardmäßig eingeschaltet.
        enabled = UserDefaults.standard.object(forKey: "dragMerge") as? Bool ?? true
        if enabled {
            start()
            if !AXIsProcessTrusted() { requestPermission() }
        }
        Log.write("Start: Ziehen \(enabled ? "an" : "aus"), Bedienungshilfen \(AXIsProcessTrusted() ? "erlaubt" : "NICHT erlaubt")")
    }

    var hasPermission: Bool { AXIsProcessTrusted() }

    /// Zeigt den macOS-Dialog für die Bedienungshilfen-Berechtigung.
    private func requestPermission() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "dragMerge")
        if on {
            if !AXIsProcessTrusted() { requestPermission() }
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.mouseDown()
        }) {
            monitors.append(monitor)
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    // MARK: - Mausverlauf

    private func mouseDown() {
        reset()
        let trusted = AXIsProcessTrusted()
        if trusted != lastTrusted {
            lastTrusted = trusted
            Log.write("Bedienungshilfen jetzt: \(trusted ? "erlaubt" : "NICHT erlaubt")")
        }
        guard trusted else { return }
        let point = Self.mousePoint()
        items = Self.dockItems(around: point)
        guard !items.isEmpty else { return }
        // Nur Apps lassen sich ziehen, keine Ordner.
        guard let hit = items.first(where: { Self.hit($0.frame, point, inset: 0) }), !Self.isFolder(hit.path) else {
            Log.write("Klick im Dock, aber nicht auf einer App (\(items.count) Symbole gefunden)")
            return
        }
        // Der Ordner-Modus startet nur nach Doppeldrücken: einmal klicken, sofort wieder drücken
        // und halten. Ein einfaches Ziehen bleibt normales Umsortieren im Dock.
        let now = Date()
        let isDouble = hit.path == lastDownPath && now.timeIntervalSince(lastDownTime) < doublePressTime
        lastDownPath = hit.path
        lastDownTime = now
        guard isDouble else { return }

        source = hit.path
        NSSound(named: "Pop")?.play() // Signal: Ordner-Modus ist an
        Log.write("Ordner-Modus (Doppeldrücken): \(hit.path)")
        upTicks = 0
        dragStart = Date()
        restPoint = point
        restSince = Date()
        shakeDirection = 0
        shakeExtreme = Self.isVertical ? point.y : point.x
        shakeTurns = []

        // Während eines Ziehvorgangs liefert macOS keine verlässlichen Mausereignisse an andere
        // Apps – deshalb die Maus selbst abfragen, bis die Taste losgelassen wird.
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func tick() {
        guard let source else { reset(); return }
        let point = Self.mousePoint()

        // Hardware-Zustand der Maustaste; erst nach zwei "oben"-Messungen gilt sie als losgelassen.
        let down = CGEventSource.buttonState(.hidSystemState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .left)
        upTicks = down ? 0 : upTicks + 1
        if upTicks >= 2 {
            // Losgelassen.
            Log.write(String(format: "Dauer %.1f s, Ende bei (%.0f, %.0f)", Date().timeIntervalSince(dragStart), point.x, point.y))
            if armed, let target {
                Log.write("Losgelassen auf \(target) -> Ordner")
                MergeAnimation.play(at: NSEvent.mouseLocation, source: source, target: target)
                // Dem Dock kurz Zeit geben, sein eigenes Loslassen zu verarbeiten.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    FolderStore.shared.merge(source: source, target: target)
                }
            } else {
                Log.write("Losgelassen ohne Ziel (Ziel: \(target ?? "keins"), lange genug gehalten: \(armed))")
            }
            reset()
            return
        }

        // Ziel bestimmen. Beim Ziehen weicht die Ziel-App im Dock aus und man folgt ihr mit der Maus –
        // oft zurück auf den alten Platz der gezogenen App. Deshalb bleibt ein einmal gewähltes Ziel
        // "kleben", solange die Maus in seiner Nähe ist und nicht klar auf einer anderen App steht.
        let hit: String?
        if let other = items.first(where: { $0.path != source && Self.hit($0.frame, point, inset: 0.1) }) {
            hit = other.path
        } else if let target, let frame = items.first(where: { $0.path == target })?.frame,
                  Self.hit(frame, point, inset: -1.0) {
            hit = target
        } else {
            hit = items.filter { $0.path != source && Self.hit($0.frame, point, inset: -0.2) }
                .min { Self.distance($0.frame, point) < Self.distance($1.frame, point) }?.path
        }

        // Die Haltezeit zählt erst, wenn die Maus still steht – so löst normales Umsortieren nichts aus.
        if hypot(point.x - restPoint.x, point.y - restPoint.y) > 10 {
            restPoint = point
            restSince = Date()
        }

        if hit != target {
            target = hit
            armed = false
            restPoint = point
            restSince = Date()
            Log.write("  über \(hit ?? "nichts")")
            overlay?.orderOut(nil)
        } else if !armed, target != nil, Date().timeIntervalSince(restSince) >= holdTime {
            armed = true
            Log.write("  bereit: Loslassen erstellt Ordner")
            NSSound(named: "Tink")?.play()
        }
        if armed { showBadge() }

        // Rütteln: schnelles Hin und Her über einer anderen App legt die App sofort in den Ordner.
        let axis = Self.isVertical ? point.y : point.x
        if shakeDirection == 0 {
            if abs(axis - shakeExtreme) >= shakeDistance {
                shakeDirection = axis > shakeExtreme ? 1 : -1
                shakeExtreme = axis
            }
        } else if (axis - shakeExtreme) * shakeDirection > 0 {
            shakeExtreme = axis // weiter in dieselbe Richtung
        } else if abs(axis - shakeExtreme) >= shakeDistance {
            shakeDirection = -shakeDirection
            shakeExtreme = axis
            shakeTurns.append(Date())
        }
        shakeTurns.removeAll { Date().timeIntervalSince($0) > 0.9 }
        guard shakeTurns.count >= 3 else { return }
        shakeTurns = []

        let shakeTarget = target ?? items.filter { $0.path != source && Self.hit($0.frame, point, inset: -0.6) }
            .min { Self.distance($0.frame, point) < Self.distance($1.frame, point) }?.path
        guard let shakeTarget else {
            Log.write("  Rütteln erkannt, aber keine andere App in der Nähe")
            return
        }
        Log.write("  Rütteln erkannt über \(shakeTarget) -> Ordner")
        NSSound(named: "Tink")?.play()
        MergeAnimation.play(at: NSEvent.mouseLocation, source: source, target: shakeTarget)
        reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            FolderStore.shared.merge(source: source, target: shakeTarget)
        }
    }

    private static func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        isVertical ? abs(frame.midY - point.y) : abs(frame.midX - point.x)
    }

    private static var isVertical: Bool {
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        return orientation == "left" || orientation == "right"
    }

    /// Grünes „+1" rechts oben am gezogenen Symbol: Loslassen legt die App in einen Ordner.
    private func showBadge() {
        let size = NSSize(width: 40, height: 26)
        if overlay == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = true
            // Über dem gezogenen Symbol, das macOS sehr weit oben zeichnet.
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .transient]

            let pill = NSView(frame: NSRect(origin: .zero, size: size))
            pill.wantsLayer = true
            pill.layer?.backgroundColor = NSColor.systemGreen.cgColor
            pill.layer?.cornerRadius = size.height / 2
            pill.layer?.borderColor = NSColor.white.cgColor
            pill.layer?.borderWidth = 2

            let label = NSTextField(labelWithString: "+1")
            label.font = .systemFont(ofSize: 15, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.sizeToFit()
            label.frame = NSRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)
            pill.addSubview(label)
            window.contentView = pill
            overlay = window
        }
        let mouse = NSEvent.mouseLocation
        overlay?.setFrameOrigin(NSPoint(x: mouse.x + 14, y: mouse.y + 14))
        overlay?.orderFrontRegardless()
    }

    private func reset() {
        overlay?.orderOut(nil)
        poll?.invalidate()
        poll = nil
        armed = false
        source = nil
        target = nil
        items = []
    }

    // MARK: - Dock auslesen

    /// Liegt `point` auf `frame`? Geprüft wird nur entlang der Dock-Leiste; quer dazu reicht es,
    /// nah am Bildschirmrand zu sein. Grund: Bei automatisch ausgeblendetem Dock meldet macOS die
    /// Positionen des versteckten Docks, also quer zur Leiste verschoben.
    static func hit(_ frame: CGRect, _ point: CGPoint, inset: CGFloat) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: point.x, y: primaryHeight - point.y))
        } ?? NSScreen.screens.first
        guard let bounds = screen?.frame else { return false }
        let top = primaryHeight - bounds.maxY, bottom = primaryHeight - bounds.minY
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        switch orientation {
        case "left":
            let band = frame.width + 60
            return point.x <= bounds.minX + band
                && point.y >= frame.minY + frame.height * inset && point.y <= frame.maxY - frame.height * inset
                && point.y >= top
        case "right":
            let band = frame.width + 60
            return point.x >= bounds.maxX - band
                && point.y >= frame.minY + frame.height * inset && point.y <= frame.maxY - frame.height * inset
        default:
            let band = frame.height + 60
            return point.y >= bottom - band
                && point.x >= frame.minX + frame.width * inset && point.x <= frame.maxX - frame.width * inset
        }
    }

    static func isFolder(_ path: String) -> Bool {
        path.hasPrefix(FolderBuilder.bundlesDirectory.path + "/")
    }

    /// Mausposition in Bildschirmkoordinaten mit Ursprung oben links (wie die Bedienungshilfen).
    static func mousePoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: height - location.y)
    }

    /// Alle App-Symbole im Dock mit Position – leer, wenn `point` gar nicht im Dock liegt.
    static func dockItems(around point: CGPoint, quiet: Bool = false) -> [Item] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            if !quiet { Log.write("Dock-Prozess nicht gefunden") }
            return []
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let top = children(of: app)
        guard let list = top.first(where: { role(of: $0) == "AXList" }) ?? top.first else {
            if !quiet { Log.write("Dock liefert keine Elemente (Bedienungshilfen-Zugriff verweigert?)") }
            return []
        }
        // Nur weitermachen, wenn der Klick im Dock-Bereich liegt.
        guard let listFrame = frame(of: list) else {
            if !quiet { Log.write("Dock-Leiste ohne Position (Rollen: \(top.map { role(of: $0) ?? "?" }))") }
            return []
        }
        guard hit(listFrame, point, inset: 0) else {
            // Klicks am unteren Bildschirmrand protokollieren – hilft, falls die Koordinaten nicht passen.
            if let screen = NSScreen.screens.first, point.y > screen.frame.height - 120 {
                if !quiet { Log.write("Klick \(point) außerhalb der Dock-Leiste \(listFrame)") }
            }
            return []
        }

        let elements = children(of: list)
        let found: [Item] = elements.compactMap { element in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
                  let value, let frame = frame(of: element) else { return nil }
            let url: URL?
            if CFGetTypeID(value) == CFURLGetTypeID() {
                url = (value as! CFURL) as URL
            } else if let string = value as? String {
                url = URL(string: string) ?? URL(fileURLWithPath: string)
            } else {
                url = nil
            }
            guard let url, url.pathExtension == "app" else { return nil }
            return Item(path: url.standardizedFileURL.path, frame: frame)
        }
        if found.isEmpty {
            if !quiet { Log.write("Im Dock \(elements.count) Elemente, aber keine App erkannt (Rollen: \(Array(Set(elements.compactMap { role(of: $0) }))))") }
        }
        return found
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
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

/// Kleines Protokoll unter ~/Library/Logs/BetterDock.log zur Fehlersuche.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BetterDock.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
