// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageStats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIUsageStats", targets: ["AIUsageStats"]),
        .executable(name: "UsageCapture", targets: ["UsageCapture"]),
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "UsageCapture", dependencies: ["UsageCore"]),
        .executableTarget(name: "AIUsageStats", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ]
)
