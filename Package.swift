// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SepharimSippur",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "SepharimSippur",
            targets: ["SepharimSippurApp"]
        ),
    ],
    targets: [
        .target(name: "SepharimSippur"),
        .executableTarget(
            name: "SepharimSippurApp",
            dependencies: ["SepharimSippur"]
        ),
        .testTarget(
            name: "SepharimSippurTests",
            dependencies: ["SepharimSippur"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
