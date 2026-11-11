import AppKit
import ApplicationServices

/// Öffnet einen Dock-Ordner, sobald die Maus über seinem Symbol steht.
/// Das Popup schließt sich selbst, wenn die Maus Symbol und Popup verlässt.
final class HoverOpen: ObservableObject {
    static let shared = HoverOpen()

    @Published private(set) var enabled: Bool
    private var timer: Timer?
    private var revealed = false
    private var cache: [DragMerge.Item] = []
    private var cacheTime = Date.distantPast
    private var hovered: String?
    private var hoveredSince = Date()
    private var opened = false
    private let dwell: TimeInterval = 0.15

    private init() {
        enabled = UserDefaults.standard.object(forKey: "hoverOpen") as? Bool ?? true
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "hoverOpen")
        on ? start() : stop()
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        hovered = nil
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        guard NSEvent.pressedMouseButtons == 0,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else {
            hovered = nil
            return
        }
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let orientation = dock?.string(forKey: "orientation") ?? "bottom"
        let distance: CGFloat
        switch orientation {
        case "left": distance = mouse.x - screen.frame.minX
        case "right": distance = screen.frame.maxX - mouse.x
        default: distance = mouse.y - screen.frame.minY
        }

        // Ein automatisch ausgeblendetes Dock ist erst da, wenn die Maus den Rand berührt hat,
        // und bleibt, solange sie in seiner Nähe ist.
        let autohide = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
        if !autohide || distance <= 3 { revealed = true } else if distance > 140 { revealed = false }

        guard revealed, distance <= 110, AXIsProcessTrusted() else {
            hovered = nil
            return
        }

        let point = DragMerge.mousePoint()
        if Date().timeIntervalSince(cacheTime) > (cache.isEmpty ? 0.3 : 1.5) {
            cache = DragMerge.dockItems(around: point, quiet: true)
            cacheTime = Date()
        }
        let folder = cache.first { DragMerge.isFolder($0.path) && DragMerge.hit($0.frame, point, inset: 0.04) }

        if folder?.path != hovered {
            hovered = folder?.path
            hoveredSince = Date()
            opened = false
        } else if let folder, !opened, Date().timeIntervalSince(hoveredSince) >= dwell {
            opened = true
            open(folder, on: screen, orientation: orientation)
        }
    }

    private func open(_ folder: DragMerge.Item, on screen: NSScreen, orientation: String) {
        // Fläche des Symbols in Bildschirmkoordinaten (Ursprung unten links). Quer zur Leiste zählt
        // der Bildschirmrand, weil macOS dort die Position des versteckten Docks meldet.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = folder.frame
        let tile: NSRect
        switch orientation {
        case "left":
            tile = NSRect(x: screen.frame.minX, y: primaryHeight - frame.maxY, width: frame.width + 16, height: frame.height)
        case "right":
            tile = NSRect(x: screen.frame.maxX - frame.width - 16, y: primaryHeight - frame.maxY,
                          width: frame.width + 16, height: frame.height)
        default:
            tile = NSRect(x: frame.minX, y: screen.frame.minY, width: frame.width, height: frame.height + 16)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--hover", "\(tile.minX)", "\(tile.minY)", "\(tile.width)", "\(tile.height)"]
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: folder.path), configuration: configuration)
    }
}
