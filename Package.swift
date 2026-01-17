// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexMonitor", targets: ["CodexMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "CodexMonitor",
            path: "Sources/CodexMonitor"
        )
    ]
)
