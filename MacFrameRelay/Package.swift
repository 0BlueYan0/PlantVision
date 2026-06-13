// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacFrameRelay",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MacFrameRelayCore",
            targets: ["MacFrameRelayCore"]
        )
    ],
    targets: [
        .target(
            name: "MacFrameRelayCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacFrameRelayCoreTests",
            dependencies: ["MacFrameRelayCore"],
            resources: [
                .copy("Resources/TestPlantClassifier.mlmodel"),
                .copy("Resources/lobelia-sample.jpeg"),
                .copy("Resources/background-sample.jpg"),
                .copy("Resources/mars-sample.jpg")
            ]
        )
    ]
)
