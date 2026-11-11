import SwiftUI
import UniformTypeIdentifiers

private func appName(_ path: String) -> String {
    FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
}

struct FoldersView: View {
    @ObservedObject private var store = FolderStore.shared
    @State private var selection: DockFolder.ID?

    private var selectedIndex: Int? { store.folders.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 190)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                if let error = store.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else {
                    Text("„Übernehmen“ startet das Dock kurz neu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Übernehmen") { store.apply() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { if selection == nil { selection = store.folders.first?.id } }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.folders) { folder in
                    Label(folder.name.isEmpty ? "Ordner" : folder.name, systemImage: "square.grid.2x2")
                        .tag(folder.id)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button {
                    let folder = DockFolder(name: "Neuer Ordner")
                    store.folders.append(folder)
                    selection = folder.id
                } label: { Image(systemName: "plus") }
                    .help("Neuen Ordner anlegen")
                Button {
                    if let index = selectedIndex {
                        store.folders.remove(at: index)
                        selection = store.folders.first?.id
                    }
                } label: { Image(systemName: "minus") }
                    .disabled(selectedIndex == nil)
                    .help("Ordner löschen – die Apps kommen zurück ins Dock")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder private var detail: some View {
        if let index = selectedIndex {
            let folder = $store.folders[index]
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name des Ordners", text: folder.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                List {
                    ForEach(folder.wrappedValue.appPaths, id: \.self) { path in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 28, height: 28)
                            Text(appName(path))
                            Spacer()
                            Button {
                                folder.wrappedValue.appPaths.removeAll { $0 == path }
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .help("Aus dem Ordner entfernen")
                        }
                    }
                    .onMove { folder.wrappedValue.appPaths.move(fromOffsets: $0, toOffset: $1) }
                }
                .overlay {
                    if folder.wrappedValue.appPaths.isEmpty {
                        Text("Noch keine Apps.\nFüge welche hinzu oder ziehe sie aus dem Finder hierher.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            guard let url, url.pathExtension == "app" else { return }
                            DispatchQueue.main.async { add([url.standardizedFileURL.path], to: folder) }
                        }
                    }
                    return true
                }

                HStack {
                    Menu("App aus dem Dock hinzufügen") {
                        let taken = Set(store.folders.flatMap(\.appPaths))
                        let available = store.dockAppPaths.filter { !taken.contains($0) }
                        if available.isEmpty { Text("Alle Dock-Apps sind schon in Ordnern") }
                        ForEach(available, id: \.self) { path in
                            Button(appName(path)) { add([path], to: folder) }
                        }
                    }
                    .fixedSize()
                    Button("Andere App…") { pickApps(for: folder) }
                }
            }
            .padding(16)
        } else {
            Text("Lege links mit „+“ einen Ordner an.")
                .foregroundStyle(.secondary)
        }
    }

    private func add(_ paths: [String], to folder: Binding<DockFolder>) {
        for path in paths where !folder.wrappedValue.appPaths.contains(path) {
            folder.wrappedValue.appPaths.append(path)
        }
    }

    private func pickApps(for folder: Binding<DockFolder>) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Hinzufügen"
        if panel.runModal() == .OK {
            add(panel.urls.map { $0.standardizedFileURL.path }, to: folder)
        }
    }
}
