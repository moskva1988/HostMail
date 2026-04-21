// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HostMailCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HostMailCore", targets: ["HostMailCore"])
    ],
    targets: [
        .target(
            name: "HostMailCore",
            path: "Sources/HostMailCore",
            resources: [
                .process("Storage/HostMailStore.xcdatamodeld")
            ]
        )
    ]
)
