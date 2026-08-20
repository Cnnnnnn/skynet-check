// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkynetLoginMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SkynetMonitorCore", targets: ["SkynetMonitorCore"]),
        .executable(name: "SkynetLoginMonitor", targets: ["SkynetLoginMonitor"]),
    ],
    targets: [
        .target(name: "SkynetMonitorCore"),
        .executableTarget(
            name: "SkynetLoginMonitor",
            dependencies: ["SkynetMonitorCore"]
        ),
        .testTarget(
            name: "SkynetMonitorCoreTests",
            dependencies: ["SkynetMonitorCore"]
        ),
    ]
)
