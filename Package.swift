// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "swift-clvm-tools",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "CLVMTools",
            targets: ["CLVMTools"])
    ],
    dependencies: [
        .package(url: "git@github.com:keyspaceapp/swift-clvm.git", from: "0.0.5")
    ],
    targets: [
        .target(
            name: "CLVMTools",
            dependencies: [
                .product(name: "CLVM", package: "swift-clvm", condition: nil),
            ]),
        .testTarget(
            name: "CLVMToolsTests",
            dependencies: ["CLVMTools"]),
    ]
)
