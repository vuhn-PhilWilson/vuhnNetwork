// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "vuhnNetwork",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
        .library(
            name: "vuhnNetwork",
            targets: ["vuhnNetwork"]),
    ],
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/BlueCryptor.git", from:"1.0.32"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "vuhnNetwork",
            dependencies: ["Cryptor","NIO", "NIOHTTP1"]),
        .testTarget(
            name: "vuhnNetworkTests",
            dependencies: ["vuhnNetwork"]),
    ]
)
