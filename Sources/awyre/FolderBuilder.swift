import Foundation

/// Erzeugt für jeden Ordner eine kleine Hilfs-App, die im Dock liegt.
enum FolderBuilder {
    static var bundlesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Better Dock Ordner", isDirectory: true)
    }

    private static var helperBinary: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/awyre-folder")
    }

    /// Entfernt alle bisher erzeugten Ordner-Apps.
    static func reset() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: bundlesDirectory.path) { try fm.removeItem(at: bundlesDirectory) }
        try fm.createDirectory(at: bundlesDirectory, withIntermediateDirectories: true)
    }

    /// Baut die Ordner-App und gibt ihren Pfad zurück.
    static func build(_ folder: DockFolder, bundleName: String) throws -> URL {
        let fm = FileManager.default
        let bundle = bundlesDirectory.appendingPathComponent(bundleName + ".app", isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        try fm.copyItem(at: helperBinary, to: macOS.appendingPathComponent("awyre-folder"))

        let info: [String: Any] = [
            "CFBundleName": folder.name,
            "CFBundleDisplayName": folder.name,
            "CFBundleIdentifier": "com.awyre.folder.\(folder.id.uuidString.lowercased())",
            "CFBundleExecutable": "awyre-folder",
            "CFBundleIconFile": "icon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": String(Int(Date().timeIntervalSince1970)),
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))

        let content: [String: Any] = ["name": folder.name, "apps": folder.appPaths]
        try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted])
            .write(to: resources.appendingPathComponent("folder.json"))

        try FolderIcon.writeICNS(appPaths: folder.appPaths, to: resources.appendingPathComponent("icon.icns"))
        try Shell.run("/usr/bin/codesign", "--force", "-s", "-", bundle.path)
        return bundle
    }
}
