// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0
import PackageDescription

let package = Package(
    name: "MothText",
    platforms: [
        .macOS(.v13)
        // Linux supported implicitly.
    ],
    products: [
        .library(name: "MothTextCore", targets: ["MothTextCore"]),
        .library(name: "MothEditor", targets: ["MothEditor"]),
        .library(name: "MothWorkspace", targets: ["MothWorkspace"]),
        .library(name: "MothApplication", targets: ["MothApplication"]),
        .library(name: "MothIPC", targets: ["MothIPC"]),
        .executable(name: "MothTextPluginHost", targets: ["MothPluginHost"]),
        .executable(name: "MothTextLinux", targets: ["MothTextLinux"]),
        .executable(name: "MothTextMac", targets: ["MothTextMac"]),
    ],
    dependencies: [
        // The repository pins Luna through Dependencies/Luna-UI. In the canonical
        // Git checkout this path is a Git submodule; SwiftPM consumes it locally.
        .package(path: "Dependencies/Luna-UI"),
    ],
    targets: [
        .target(
            name: "MothTextCore"
        ),

        .target(
            name: "MothEditor",
            dependencies: ["MothTextCore"]
        ),

        .target(
            name: "MothWorkspace",
            dependencies: [
                "MothEditor",
                "MothTextCore",
            ]
        ),

        .target(
            name: "MothIPC"
        ),

        .target(
            name: "MothApplication",
            dependencies: [
                "MothEditor",
                "MothIPC",
                "MothTextCore",
                "MothWorkspace",
                .product(name: "LunaCore", package: "Luna-UI"),
                .product(name: "LunaUI", package: "Luna-UI"),
            ]
        ),

        .executableTarget(
            name: "MothPluginHost",
            dependencies: ["MothIPC"]
        ),

        .executableTarget(
            name: "MothTextLinux",
            dependencies: [
                "MothApplication",
                "MothIPC",
            ]
        ),

        .executableTarget(
            name: "MothTextMac",
            dependencies: ["MothApplication"]
        ),

        .testTarget(
            name: "MothTextCoreTests",
            dependencies: ["MothTextCore"]
        ),
        .testTarget(
            name: "MothEditorTests",
            dependencies: ["MothEditor", "MothTextCore"]
        ),
        .testTarget(
            name: "MothWorkspaceTests",
            dependencies: ["MothWorkspace", "MothEditor", "MothTextCore"]
        ),
        .testTarget(
            name: "MothIPCTests",
            dependencies: ["MothIPC"]
        ),
    ]
)
