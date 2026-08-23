// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkynetLoginMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SkynetMonitorCore", targets: ["SkynetMonitorCore"]),
        .executable(name: "SkynetLoginMonitor", targets: ["SkynetLoginMonitor"]),
        .executable(name: "skynet-status", targets: ["SkynetStatusCLI"]),
    ],
    targets: [
        .target(name: "SkynetMonitorCore"),
        .executableTarget(
            name: "SkynetLoginMonitor",
            dependencies: ["SkynetMonitorCore"]
        ),
        .executableTarget(
            name: "SkynetStatusCLI",
            dependencies: ["SkynetMonitorCore"]
        ),
        .testTarget(
            name: "SkynetMonitorCoreTests",
            dependencies: ["SkynetMonitorCore"]
        ),
    ]
)
