import AppKit
import SwiftUI

// Inhalt des Ordners, von awyre in die Resources geschrieben.
struct FolderContent: Decodable {
    let name: String
    let apps: [String]
}

struct AppEntry: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

struct FolderView: View {
    let name: String
    let apps: [AppEntry]
    let open: (AppEntry) -> Void

    var body: some View {
        let columnCount = min(max(apps.count, 1), apps.count <= 4 ? 2 : (apps.count <= 9 ? 3 : 4))
        VStack(spacing: 14) {
            Text(name)
                .font(.title2.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 10), count: columnCount), spacing: 12) {
                ForEach(apps) { app in
                    AppButton(app: app) { open(app) }
                }
            }
        }
        .padding(22)
        .fixedSize()
    }
}

enum DragState { case idle, holding, dragging }

struct AppButton: View {
    let app: AppEntry
    let action: () -> Void
    @State private var hovering = false
    @State private var state = DragState.idle
    @State private var tilt = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                // Wackeln wie am iPad, sobald die App gedrückt gehalten wird.
                .rotationEffect(.degrees(state == .holding ? (tilt ? 4 : -4) : 0))
                .opacity(state == .dragging ? 0.25 : 1)
            Text(app.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(state == .dragging ? 0.25 : 1)
        }
        .frame(width: 92, height: 92)
        .background(RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(hovering && state == .idle ? 0.12 : 0)))
        .onHover { hovering = $0 }
        .onChange(of: state) { _, newValue in
            if newValue == .holding {
                tilt = false
                withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { tilt = true }
            } else {
                withAnimation(.linear(duration: 0.05)) { tilt = false }
            }
        }
        // Klick startet die App, Ziehen aus dem Popup heraus nimmt sie aus dem Ordner.
        .overlay(DragCatcher(app: app, click: action) { state = $0 })
        .help("Klicken zum Öffnen – herausziehen, um die App aus dem Ordner zu nehmen")
    }
}

/// Unsichtbare Fläche über einem App-Symbol: unterscheidet Klick und Ziehen.
struct DragCatcher: NSViewRepresentable {
    let app: AppEntry
    let click: () -> Void
    let stateChanged: (DragState) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.app = app
        view.click = click
        view.stateChanged = stateChanged
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.click = click
        view.stateChanged = stateChanged
    }
}

final class CatcherView: NSView {
    var app: AppEntry!
    var click: (() -> Void)?
    var stateChanged: ((DragState) -> Void)?
    private var downPoint: NSPoint?
    private var dragStarted = false
    private var holdTimer: DispatchWorkItem?
    private var ghost: NSWindow?
    private let ghostSide: CGFloat = 96

    // Auch der erste Klick zählt, wenn das Popup nicht die aktive App ist.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragStarted = false
        let timer = DispatchWorkItem { [weak self] in
            guard let self, !self.dragStarted, self.downPoint != nil else { return }
            self.stateChanged?(.holding)
        }
        holdTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: timer)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint else { return }
        if !dragStarted {
            let point = event.locationInWindow
            guard hypot(point.x - downPoint.x, point.y - downPoint.y) > 6 else { return }
            dragStarted = true
            holdTimer?.cancel()
            (NSApp.delegate as? FolderDelegate)?.dragging = true
            stateChanged?(.dragging)
            showGhost()
        }
        moveGhost()
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.cancel()
        downPoint = nil
        stateChanged?(.idle)
        guard dragStarted else {
            click?()
            return
        }
        dragStarted = false
        (NSApp.delegate as? FolderDelegate)?.dragging = false

        let mouse = NSEvent.mouseLocation
        let ghostWindow = ghost
        ghost = nil
        guard let frame = window?.frame, !frame.insetBy(dx: -10, dy: -10).contains(mouse) else {
            ghostWindow?.orderOut(nil)
            return
        }

        // Außerhalb des Ordners losgelassen: Das Symbol "verpufft", dann nimmt Better Dock die App heraus.
        (NSApp.delegate as? FolderDelegate)?.launching = true // Popup darf sich jetzt nicht selbst schließen
        window?.orderOut(nil)
        if let icon = ghostWindow?.contentView?.layer?.sublayers?.first {
            icon.removeAnimation(forKey: "wiggle")
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 1.25
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let poof = CAAnimationGroup()
            poof.animations = [grow, fade]
            poof.duration = 0.28
            poof.timingFunction = CAMediaTimingFunction(name: .easeOut)
            icon.opacity = 0
            icon.add(poof, forKey: "poof")
        }
        let path = app.url.path
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ghostWindow?.orderOut(nil)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.awyre.dock.removeFromFolder"), object: nil,
                userInfo: ["app": path, "bundle": Bundle.main.bundlePath], deliverImmediately: true)
            NSApp.terminate(nil)
        }
    }

    /// Das gezogene Symbol: eigenes kleines Fenster, damit es beim Ziehen wackeln kann.
    private func showGhost() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ghostSide, height: ghostSide),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: ghostSide, height: ghostSide))
        content.wantsLayer = true
        let icon = CALayer()
        let side: CGFloat = 72
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.position = CGPoint(x: ghostSide / 2, y: ghostSide / 2)
        icon.contents = app.icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        icon.contentsGravity = .resizeAspect
        icon.shadowOpacity = 0.35
        icon.shadowRadius = 6
        icon.shadowOffset = CGSize(width: 0, height: -3)
        content.layer?.addSublayer(icon)

        let wiggle = CABasicAnimation(keyPath: "transform.rotation.z")
        wiggle.fromValue = -0.07
        wiggle.toValue = 0.07
        wiggle.duration = 0.12
        wiggle.autoreverses = true
        wiggle.repeatCount = .infinity
        wiggle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        icon.add(wiggle, forKey: "wiggle")

        window.contentView = content
        ghost = window
        moveGhost()
        window.orderFrontRegardless()
    }

    private func moveGhost() {
        let mouse = NSEvent.mouseLocation
        ghost?.setFrameOrigin(NSPoint(x: mouse.x - ghostSide / 2, y: mouse.y - ghostSide / 2))
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { NSApp.terminate(nil) } // Esc
}

final class FolderDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: KeyPanel!
    var launching = false
    var dragging = false
    /// Im Hover-Modus (von Better Dock per Überfahren geöffnet): Fläche des Dock-Symbols.
    private var hoverTile: NSRect?
    private var lastInside = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = Bundle.main.url(forResource: "folder", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(FolderContent.self, from: data) else {
            NSApp.terminate(nil)
            return
        }
        let apps = content.apps
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { AppEntry(url: URL(fileURLWithPath: $0)) }

        let host = NSHostingView(rootView: FolderView(name: content.name, apps: apps) { [weak self] app in
            self?.launch(app)
        })
        let size = host.fittingSize

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 26
        blur.layer?.masksToBounds = true
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--hover"), arguments.count > index + 4 {
            let values = arguments[(index + 1)...(index + 4)].compactMap { Double($0) }
            if values.count == 4 { hoverTile = NSRect(x: values[0], y: values[1], width: values[2], height: values[3]) }
        }

        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: hoverTile == nil ? [.borderless] : [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.contentView = blur
        panel.delegate = self
        panel.setFrameOrigin(origin(for: size))

        // NSPanel versteckt sich sonst, solange die App (noch) nicht aktiv ist.
        panel.hidesOnDeactivate = false
        panel.orderFrontRegardless()
        if hoverTile == nil {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        } else {
            // Offen bleiben, solange die Maus über Symbol oder Popup ist.
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.checkHover() }
            RunLoop.main.add(timer, forMode: .common)
        }

        // Klick irgendwo außerhalb schließt den Ordner – auch falls das Popup nie den Fokus bekam.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.launching == false && self?.dragging == false { NSApp.terminate(nil) }
        }
    }

    private func checkHover() {
        guard let tile = hoverTile, !launching, !dragging else { return }
        let mouse = NSEvent.mouseLocation
        // Symbol, Popup und der Weg dazwischen zählen als "darüber".
        let bridge = tile.union(panel.frame)
        let corridor = NSRect(x: max(tile.minX, panel.frame.minX) - 12, y: bridge.minY,
                              width: min(tile.maxX, panel.frame.maxX) - max(tile.minX, panel.frame.minX) + 24,
                              height: bridge.height)
        let inside = panel.frame.insetBy(dx: -14, dy: -14).contains(mouse)
            || tile.insetBy(dx: -6, dy: -6).contains(mouse) || corridor.contains(mouse)
        if inside { lastInside = Date() }
        if Date().timeIntervalSince(lastInside) > 0.3 { NSApp.terminate(nil) }
    }

    /// Platziert das Popup neben dem Dock-Symbol (im Hover-Modus) bzw. der Mausposition.
    private func origin(for size: NSSize) -> NSPoint {
        var mouse = NSEvent.mouseLocation
        if let tile = hoverTile { mouse = NSPoint(x: tile.midX, y: tile.midY) }
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let frame = screen.frame
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        let gap: CGFloat = 56
        var point: NSPoint
        switch orientation {
        case "left": point = NSPoint(x: mouse.x + gap, y: mouse.y - size.height / 2)
        case "right": point = NSPoint(x: mouse.x - gap - size.width, y: mouse.y - size.height / 2)
        default: point = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + gap)
        }
        point.x = min(max(point.x, frame.minX + 12), frame.maxX - size.width - 12)
        point.y = min(max(point.y, frame.minY + 12), frame.maxY - size.height - 36)
        return point
    }

    private func launch(_ app: AppEntry) {
        launching = true
        panel.orderOut(nil)
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // Klick daneben schließt den Ordner.
    func windowDidResignKey(_ notification: Notification) {
        if !launching && !dragging { NSApp.terminate(nil) }
    }

    // Erneuter Klick auf das Dock-Symbol schließt den Ordner.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hoverTile != nil { return false } // per Überfahren geöffnet: bleibt offen
        NSApp.terminate(nil)
        return false
    }
}

let app = NSApplication.shared
let delegate = FolderDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
