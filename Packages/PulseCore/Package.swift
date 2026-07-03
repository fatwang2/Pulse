// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"])
    ],
    targets: [
        .target(name: "PulseCore"),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"])
    ]
)
