// swift-tools-version: 5.9
import PackageDescription
var targets: [Target] = [
    .target(name: "DisplayCore"),
    .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"])
]
#if os(macOS)
targets.append(.executableTarget(name: "BDMenu", dependencies: ["DisplayCore"]))
#endif
let package = Package(name: "BDMenu", platforms: [.macOS(.v14)], targets: targets)
