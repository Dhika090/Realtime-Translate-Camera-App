// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RealtimeTranslateApp",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RealtimeTranslateApp",
            targets: ["RealtimeTranslateApp"]
        )
    ],
    targets: [
        .target(
            name: "RealtimeTranslateApp",
            path: "RealtimeTranslateApp",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "RealtimeTranslateAppTests",
            dependencies: ["RealtimeTranslateApp"],
            path: "Tests/RealtimeTranslateAppTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
