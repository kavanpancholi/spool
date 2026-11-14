// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Spool",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "Spool", targets: ["Spool"]),
  ],
  targets: [
    .target(name: "SpoolCore"),
    .target(name: "SpoolMac", dependencies: ["SpoolCore"]),
    .executableTarget(name: "Spool", dependencies: ["SpoolCore", "SpoolMac"]),
    .testTarget(name: "SpoolCoreTests", dependencies: ["SpoolCore"]),
  ]
)
