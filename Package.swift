// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GoveeMacController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GoveeMacController", targets: ["GoveeMacController"])
    ],
    targets: [
        .executableTarget(
            name: "GoveeMacController",
            resources: [
                .process("Assets")
            ]
        ),
        .testTarget(
            name: "GoveeMacControllerTests",
            dependencies: ["GoveeMacController"]
        ),
    ]
)
