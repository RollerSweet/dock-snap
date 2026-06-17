// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockSnap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DockSnap", path: "Sources")
    ]
)
