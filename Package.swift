// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Typewriter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Typewriter", targets: ["Typewriter"])],
    targets: [
        .target(name: "TypewriterCore"),
        .executableTarget(name: "Typewriter", dependencies: ["TypewriterCore"], resources: [.copy("Resources/Sounds")]),
        .testTarget(name: "TypewriterCoreTests", dependencies: ["TypewriterCore"])
    ]
)
