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
        ),
        .executable(
            name: "MacFrameRelayApp",
            targets: ["MacFrameRelayApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", .upToNextMinor(from: "16.1.1"))
    ],
    targets: [
        .target(
            name: "MacFrameRelayCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacFrameRelayApp",
            dependencies: [
                "MacFrameRelayCore",
                .product(name: "SocketIO", package: "socket.io-client-swift")
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
