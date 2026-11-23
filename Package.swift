// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TradingLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TradingLab", targets: ["TradingLab"])
    ],
    targets: [
        .executableTarget(
            name: "TradingLab",
            path: "Sources/TradingLab"
        )
    ]
)
