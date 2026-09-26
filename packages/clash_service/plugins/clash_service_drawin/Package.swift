// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "clash_service",

    platforms: [
        .macOS(.v13)
    ],

    products: [
        .library(
            name: "clash-service",
            type: .dynamic,
            targets: ["clash_service"]
        )
    ],

    targets: [
        .target(
            name: "clash_service",
            path: "Sources/vpn_service",
        )
    ]
)
