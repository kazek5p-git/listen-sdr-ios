// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ListenSDRCore",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "ListenSDRCore",
      targets: ["ListenSDRCore"]
    ),
  ],
  targets: [
    .target(
      name: "ListenSDRCore"
    ),
    .testTarget(
      name: "ListenSDRCoreTests",
      dependencies: ["ListenSDRCore"],
      resources: [
        .copy("Fixtures"),
      ]
    ),
  ]
)
