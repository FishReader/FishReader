// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FishReader",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FishReader", path: "Sources/FishReader")
    ]
)
