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
        .package(url: "https://github.com/IBM-Swift/BlueSocket.git", from:"1.0.52"),
        .package(url: "https://github.com/IBM-Swift/BlueCryptor.git", from:"1.0.32"),
    ],
    targets: [
        .target(
            name: "vuhnNetwork",
            dependencies: ["Socket", "Cryptor"]),
        .testTarget(
            name: "vuhnNetworkTests",
            dependencies: ["vuhnNetwork"]),
    ]
)
