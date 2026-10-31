// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "UsageHistory", targets: ["UsageHistory"])
]
var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7")
]
var targets: [Target] = [
    .target(name: "UsageHistory", dependencies: [.product(name: "libzstd", package: "zstd")]),
    .testTarget(name: "UsageHistoryTests", dependencies: ["UsageHistory"])
]

#if os(macOS)
products += [
    .executable(name: "AIUsageStats", targets: ["AIUsageStats"]),
    .executable(name: "UsageCapture", targets: ["UsageCapture"]),
    .library(name: "UsageCore", targets: ["UsageCore"])
]
dependencies.append(.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"))
targets += [
    .target(name: "UsageCore"),
    .target(name: "UsageHistoryStore", dependencies: ["UsageHistory", .product(name: "GRDB", package: "GRDB.swift")]),
    .executableTarget(name: "UsageCapture", dependencies: ["UsageCore"]),
    .executableTarget(name: "AIUsageStats", dependencies: ["UsageCore", "UsageHistory", "UsageHistoryStore",
                                                             .product(name: "GRDB", package: "GRDB.swift")],
                      resources: [.copy("Resources/ProviderIcons")]),
    .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    .testTarget(name: "UsageHistoryStoreTests", dependencies: ["UsageHistoryStore"]),
    .testTarget(name: "AIUsageStatsTests", dependencies: ["AIUsageStats", "UsageCore"])
]
#endif

let package = Package(
    name: "AIUsageStats",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
