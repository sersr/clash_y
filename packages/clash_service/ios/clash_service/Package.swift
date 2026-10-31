// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "clash_service",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(name: "clash-service", targets: ["clash_service"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "clash_service",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      linkerSettings: [
        .linkedFramework("NetworkExtension")
      ]
    )
  ]
)
