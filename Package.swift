// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BDMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BDMenu",
            path: "Sources/BDMenu"
        )
    ]
)
