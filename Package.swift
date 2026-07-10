// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YTMusicMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "YTMusicMac",
            path: "Sources/YTMusicMac",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "YTMusicMacTests",
            dependencies: ["YTMusicMac"],
            path: "Tests/YTMusicMacTests"
        )
    ]
)
