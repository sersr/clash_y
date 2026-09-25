// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "clash_service_drawin",
    platforms: [
        .macOS("13.0")
    ],
    products: [
        .library(name: "clash-service-drawin",type: .dynamic, targets: ["clash_service_drawin"]),
    ],
    targets: [
        .target(
            name: "clash_service_drawin",
            path: "Sources/vpn_service"
        ),
    ]
)
