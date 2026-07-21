// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MotrixNative",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "MotrixNative", targets: ["MotrixNative"])
  ],
  targets: [
    .executableTarget(
      name: "MotrixNative",
      path: "Sources/MotrixNative"
    )
  ]
)
