// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "awyre",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "awyre", path: "Sources/awyre"),
        // Popup, das beim Klick auf einen Dock-Ordner erscheint.
        .executableTarget(name: "awyre-folder", path: "Sources/awyre-folder"),
    ]
)
