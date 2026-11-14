// swift-tools-version: 6.0

import PackageDescription

let appKitSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
  name: "Spool",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "Spool", targets: ["Spool"]),
  ],
  targets: [
    .target(name: "SpoolCore"),
    .target(name: "SpoolMac", dependencies: ["SpoolCore"], swiftSettings: appKitSettings),
    .executableTarget(name: "Spool", dependencies: ["SpoolCore", "SpoolMac"], swiftSettings: appKitSettings),
    .testTarget(name: "SpoolCoreTests", dependencies: ["SpoolCore"]),
  ]
)
