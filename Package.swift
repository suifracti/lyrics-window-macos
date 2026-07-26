// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyLyrics",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SpotifyLyrics",
            targets: ["SpotifyLyrics"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SpotifyLyrics",
            dependencies: [],
            path: "Sources/SpotifyLyrics"
        )
    ]
)
