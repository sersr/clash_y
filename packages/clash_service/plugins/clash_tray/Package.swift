// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClashTray",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "ClashTray", targets: ["ClashTray"]),
    ],
    targets: [
        .executableTarget(
            name: "ClashTray",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
    ]
)
