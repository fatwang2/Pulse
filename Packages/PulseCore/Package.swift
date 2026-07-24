// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"])
    ],
    targets: [
        .target(name: "LongbridgeCABI"),
        .target(
            name: "PulseCore",
            dependencies: [
                .target(name: "LongbridgeCABI", condition: .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"])
    ]
)
