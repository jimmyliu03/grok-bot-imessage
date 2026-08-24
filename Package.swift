// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "GrokBot",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "GrokBotCore", targets: ["GrokBotCore"]),
    .executable(name: "GrokBot", targets: ["GrokBotApp"]),
  ],
  targets: [
    .target(
      name: "GrokBotCore",
      path: "Sources/GrokBotCore"
    ),
    .executableTarget(
      name: "GrokBotApp",
      dependencies: ["GrokBotCore"],
      path: "Sources/GrokBotApp"
    ),
    .testTarget(
      name: "GrokBotCoreTests",
      dependencies: ["GrokBotCore"],
      path: "Tests/GrokBotCoreTests"
    ),
  ],
  swiftLanguageModes: [.v5]
)
