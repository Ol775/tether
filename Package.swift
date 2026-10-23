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
        .target(
            name: "CTizenXML",
            linkerSettings: [.linkedLibrary("xml2")]
        ),
        .target(
            name: "TetherCore",
            dependencies: ["CTizenXML"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "Tether", dependencies: ["TetherCore"]),
        .testTarget(
            name: "TetherCoreTests",
            dependencies: ["TetherCore", "CTizenXML"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
