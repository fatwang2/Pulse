// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseUI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PulseUI", targets: ["PulseUI"])
    ],
    dependencies: [
        .package(path: "../PulseCore")
    ],
    targets: [
        .target(name: "PulseUI", dependencies: ["PulseCore"])
    ]
)
