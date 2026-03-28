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
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", exact: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SepharimSippur",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper"),
            ]
        ),
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
