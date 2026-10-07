// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrashToss",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TrashToss", path: "Sources/TrashToss")
    ]
)
