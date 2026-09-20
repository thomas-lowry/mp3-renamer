// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MP3Renamer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MP3Renamer", targets: ["MP3Renamer"])],
    targets: [
        .executableTarget(name: "MP3Renamer"),
        .testTarget(name: "MP3RenamerTests", dependencies: ["MP3Renamer"])
    ]
)
