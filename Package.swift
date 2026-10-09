// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [
  .treatAllWarnings(as: .error)
]

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
    .target(name: "DockPeekCore", swiftSettings: strictSettings),
    .target(name: "DockPeekRuntime", dependencies: ["DockPeekCore"], swiftSettings: strictSettings),
    .executableTarget(
      name: "DockPeekSettings", dependencies: ["DockPeekCore", "DockPeekRuntime"],
      swiftSettings: strictSettings),
    .executableTarget(
      name: "DockPeekWorker", dependencies: ["DockPeekCore", "DockPeekRuntime"],
      swiftSettings: strictSettings),
    .executableTarget(name: "DockTileProbe", swiftSettings: strictSettings),
    .executableTarget(
      name: "DockBounceFilter", path: "Experiments/BounceFilter", swiftSettings: strictSettings),
    .executableTarget(
      name: "BadgeFixture", path: "Experiments/BadgeFixture", swiftSettings: strictSettings),
    .executableTarget(
      name: "BounceFixture", path: "Experiments/BounceFixture", swiftSettings: strictSettings),
    .testTarget(
      name: "DockPeekTests", dependencies: ["DockPeekCore", "DockPeekRuntime", "DockPeekSettings"],
      swiftSettings: strictSettings),
  ],
  swiftLanguageModes: [.v6]
)
