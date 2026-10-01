// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mousip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Mousip", path: "Sources/Mousip")
    ]
)
