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

struct AppButton: View {
    let app: AppEntry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(app.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 92, height: 92)
            .background(RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(hovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { NSApp.terminate(nil) } // Esc
}

final class FolderDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: KeyPanel!
    private var launching = false

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

        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless], backing: .buffered, defer: false)
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()

        // Klick irgendwo außerhalb schließt den Ordner – auch falls das Popup nie den Fokus bekam.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.launching == false { NSApp.terminate(nil) }
        }
    }

    /// Platziert das Popup neben dem angeklickten Dock-Symbol (= Mausposition).
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
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
        if !launching { NSApp.terminate(nil) }
    }

    // Erneuter Klick auf das Dock-Symbol schließt den Ordner.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.terminate(nil)
        return false
    }
}

let app = NSApplication.shared
let delegate = FolderDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
