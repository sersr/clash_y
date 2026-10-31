// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClashWakeMonitor",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "ClashWakeMonitor",
            type: .dynamic,
            targets: ["ClashWakeMonitor"]
        ),
    ],
    targets: [
        .target(
            name: "ClashWakeMonitor",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
    ]
)
