// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "packagejam",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "packagejam"),
        .testTarget(name: "packagejamTests", dependencies: ["packagejam"]),
    ]
)
