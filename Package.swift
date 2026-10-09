// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DockPeek",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "DockPeekCore", targets: ["DockPeekCore"]),
    .executable(name: "DockPeekSettings", targets: ["DockPeekSettings"]),
    .executable(name: "DockPeekWorker", targets: ["DockPeekWorker"]),
    .executable(name: "DockTileProbe", targets: ["DockTileProbe"]),
  ],
  targets: [
    .target(name: "DockPeekCore"),
    .executableTarget(name: "DockPeekSettings", dependencies: ["DockPeekCore"]),
    .executableTarget(name: "DockPeekWorker", dependencies: ["DockPeekCore"]),
    .executableTarget(name: "DockTileProbe"),
    .executableTarget(name: "DockBounceFilter", path: "Experiments/BounceFilter"),
    .executableTarget(name: "BadgeFixture", path: "Experiments/BadgeFixture"),
    .executableTarget(name: "BounceFixture", path: "Experiments/BounceFixture"),
    .testTarget(name: "DockPeekTests", dependencies: ["DockPeekCore", "DockPeekSettings"]),
  ]
)
