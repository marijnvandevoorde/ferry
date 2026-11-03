// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FujiKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FujiKit", targets: ["FujiKit"]),
        .executable(name: "ferryctl", targets: ["ferryctl"]),
    ],
    targets: [
        .target(name: "FujiKit", resources: [.process("Resources")]),
        .executableTarget(name: "ferryctl", dependencies: ["FujiKit"]),
        .testTarget(name: "FujiKitTests", dependencies: ["FujiKit"]),
    ]
)
