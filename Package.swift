// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tether",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TetherCore", targets: ["TetherCore"]),
        .executable(name: "Tether", targets: ["Tether"]),
    ],
    targets: [
        .target(name: "TetherCore", resources: [.process("Resources")]),
        .executableTarget(name: "Tether", dependencies: ["TetherCore"]),
        .testTarget(
            name: "TetherCoreTests",
            dependencies: ["TetherCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
