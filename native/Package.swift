// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Translate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Translate",
            path: "Sources/Translate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
