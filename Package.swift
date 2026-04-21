// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spotdark",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SpotdarkCore", targets: ["SpotdarkCore"]),
        .executable(name: "SpotdarkApp", targets: ["SpotdarkApp"])
    ],
    targets: [
        .target(
            name: "SpotdarkCore",
            dependencies: []
        ),
        .executableTarget(
            name: "SpotdarkApp",
            dependencies: ["SpotdarkCore"]
        ),
        .testTarget(
            name: "SpotdarkCoreTests",
            dependencies: ["SpotdarkCore"]
        )
    ]
)
