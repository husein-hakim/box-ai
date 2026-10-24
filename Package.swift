// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoxingCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BoxingCore", targets: ["BoxingCore"])],
    targets: [
        .target(name: "BoxingCore", path: "ios/Boxing",
                exclude: ["Services/QwenDeveloperConfiguration.swift.example", "BoxingApp.swift", "Design", "Features", "Session", "Services/BarcodeLookup.swift", "Services/SubscriptionStore.swift", "Services/VideoFrames.swift", "Camera"],
                sources: ["Core", "Models", "Services/QwenClient.swift", "Services/QwenDeveloperConfiguration.swift", "Recognition/Camera"],
                resources: [.process("Recognition/Resources")]),
        .testTarget(name: "BoxingCoreTests", dependencies: ["BoxingCore"], path: "Tests/BoxingCoreTests")
    ]
)
