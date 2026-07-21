// swift-tools-version: 6.0
import PackageDescription

// Targets stay in Swift 5 language mode: the app wraps callback-heavy AppKit/AVFoundation
// APIs where Swift 6 strict concurrency adds churn without safety we need yet.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Ghostwriter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "GhostwriterCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: swift5),
        .target(
            name: "GhostwriterML",
            dependencies: [
                "GhostwriterCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: swift5),
        .executableTarget(
            name: "Ghostwriter",
            dependencies: ["GhostwriterCore", "GhostwriterML"],
            swiftSettings: swift5),
        .executableTarget(
            name: "ghostwriter-harness",
            dependencies: ["GhostwriterCore", "GhostwriterML"],
            swiftSettings: swift5),
        .testTarget(
            name: "GhostwriterCoreTests",
            dependencies: ["GhostwriterCore"],
            swiftSettings: swift5),
    ]
)
