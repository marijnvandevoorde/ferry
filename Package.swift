// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FerryKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FerryKit", targets: ["FerryKit"]),
        .executable(name: "ferryctl", targets: ["ferryctl"]),
    ],
    targets: [
        .target(name: "FerryKit", resources: [.process("Resources")]),
        .executableTarget(name: "ferryctl", dependencies: ["FerryKit"]),
        .testTarget(name: "FerryKitTests", dependencies: ["FerryKit"]),
    ]
)
