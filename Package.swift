// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FujiKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FujiKit", targets: ["FujiKit"]),
        .executable(name: "fujictl", targets: ["fujictl"]),
    ],
    targets: [
        .target(name: "FujiKit"),
        .executableTarget(name: "fujictl", dependencies: ["FujiKit"]),
        .testTarget(name: "FujiKitTests", dependencies: ["FujiKit"]),
    ]
)
