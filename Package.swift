// swift-tools-version:5.9
import PackageDescription

// FrameCore  - portable layout math + painter (no Apple frameworks); also builds on Linux.
// FrameKit   - Core Graphics / ImageIO / Core Text backend, image loading and export (macOS only).
// frame-cli  - command line front end used by CI.
// LightSufferFrame - the SwiftUI app (macOS only).

var targets: [Target] = [
    .target(name: "FrameCore"),
    .target(name: "FrameKit", dependencies: ["FrameCore"]),
    .executableTarget(name: "frame-cli", dependencies: ["FrameCore", "FrameKit"]),
    .testTarget(name: "FrameCoreTests", dependencies: ["FrameCore"]),
]

var products: [Product] = [
    .executable(name: "frame-cli", targets: ["frame-cli"]),
]

#if os(macOS)
targets.append(.executableTarget(name: "LightSufferFrame", dependencies: ["FrameCore", "FrameKit"]))
targets.append(.testTarget(name: "FrameKitTests", dependencies: ["FrameCore", "FrameKit"]))
products.append(.executable(name: "LightSufferFrame", targets: ["LightSufferFrame"]))
#endif

let package = Package(
    name: "LightSufferFrame",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
