import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKey.register { DockController.shared.toggle() }
        _ = DragMerge.shared // startet die Maus-Beobachtung, falls eingeschaltet
        // Erlaubt die Steuerung von außen (Skripte, Kurzbefehle).
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.awyre.dock.toggle"), object: nil, queue: .main) { _ in
            DockController.shared.toggle()
        }
        center.addObserver(forName: Notification.Name("com.awyre.dock.applyFolders"), object: nil, queue: .main) { _ in
            FolderStore.shared.load()
            FolderStore.shared.apply()
        }
        center.addObserver(forName: Notification.Name("com.awyre.dock.removeFromFolder"), object: nil, queue: .main) { note in
            guard let app = note.userInfo?["app"] as? String,
                  let bundle = note.userInfo?["bundle"] as? String else { return }
            FolderStore.shared.remove(app: app, fromBundle: bundle)
        }
        center.addObserver(forName: Notification.Name("com.awyre.dock.merge"), object: nil, queue: .main) { note in
            guard let source = note.userInfo?["source"] as? String,
                  let target = note.userInfo?["target"] as? String else { return }
            FolderStore.shared.merge(source: source, target: target)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var dock: DockController
    @ObservedObject var drag = DragMerge.shared
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button(dock.isHidden ? "Rechte Dock-Seite einblenden" : "Rechte Dock-Seite ausblenden") {
            dock.toggle()
        }
        Text("Tastenkürzel: ⌃⌥⌘D")

        Divider()

        Button("Ordner verwalten…") {
            openWindow(id: "folders")
            NSApp.activate(ignoringOtherApps: true)
        }
        Toggle("Ordner per Ziehen im Dock erstellen", isOn: Binding(get: { drag.enabled }, set: { drag.setEnabled($0) }))
        if drag.enabled && !drag.hasPermission {
            Button("⚠️ Bedienungshilfen erlauben…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }

        Divider()

        Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Better Dock beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@main
struct AwyreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var dock = DockController.shared

    var body: some Scene {
        MenuBarExtra("Better Dock", systemImage: dock.isHidden ? "dock.arrow.down.rectangle" : "dock.rectangle") {
            MenuContent(dock: dock)
        }

        Window("Better Dock – Ordner", id: "folders") {
            FoldersView()
        }
        .windowResizability(.contentMinSize)
    }
}
