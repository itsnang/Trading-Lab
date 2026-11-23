// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TradingLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TradingLab", targets: ["TradingLab"]),
        .library(name: "TradingLabCore", targets: ["TradingLabCore"])
    ],
    targets: [
        .target(
            name: "TradingLabCore",
            path: "Sources/TradingLab"
        ),
        .executableTarget(
            name: "TradingLab",
            dependencies: ["TradingLabCore"],
            path: "Sources/TradingLabEntry"
        ),
        .testTarget(
            name: "TradingLabTests",
            dependencies: ["TradingLabCore"],
            path: "Tests/TradingLabTests"
        )
    ]
)
