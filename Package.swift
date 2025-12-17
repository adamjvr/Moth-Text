// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MothText",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "IPC", targets: ["IPC"]),
        .executable(name: "MothTextPluginHost", targets: ["PluginHost"]),
        .executable(name: "MothTextLinux", targets: ["LinuxApp"]),
        .executable(name: "MothTextMac", targets: ["MacApp"]),
    ],
    targets: [
        .target(
            name: "IPC",
            path: "src/IPC"
        ),

        .executableTarget(
            name: "PluginHost",
            dependencies: ["IPC"],
            path: "src/PluginHost"
        ),

        // NOTE:
        // - Phase 0 uses a CLI client on Linux to verify IPC.
        // - In Phase 0b we will introduce GTK4 and a proper Linux UI target.
        .executableTarget(
            name: "LinuxApp",
            dependencies: ["IPC"],
            path: "src/Apps/Linux"
        ),

        // Stub: In Phase 0b/1 we’ll convert this into a real SwiftUI .app target
        // via Xcode (or a proper app-bundle build setup).
        .executableTarget(
            name: "MacApp",
            dependencies: ["IPC"],
            path: "src/Apps/Mac"
        ),
    ]
)
