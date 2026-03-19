// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Filechute",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "FilechuteCore", targets: ["FilechuteCore"]),
    ],
    targets: [
        .target(
            name: "FilechuteCore"
        ),
        .executableTarget(
            name: "Filechute",
            dependencies: ["FilechuteCore"]
        ),
        .testTarget(
            name: "FilechuteCoreTests",
            dependencies: ["FilechuteCore"]
        ),
    ]
)
