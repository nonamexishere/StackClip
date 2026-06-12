// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StackClip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StackClip",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
