// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotaCore", targets: ["QuotaCore"]),
        .executable(name: "CodexQuota", targets: ["CodexQuota"]),
        .executable(name: "QuotaBarUpdater", targets: ["QuotaBarUpdater"])
    ],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "QuotaBarUpdater", dependencies: ["QuotaCore"]),
        .executableTarget(name: "CodexQuota", dependencies: ["QuotaCore"], resources: [.copy("Resources")]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .testTarget(name: "CodexQuotaTests", dependencies: ["CodexQuota"])
    ]
)
