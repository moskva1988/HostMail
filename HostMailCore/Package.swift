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
        // MailCore2 as a local XCFramework. Build it once via:
        //   ./scripts/setup-mailcore.sh
        // (script uses Carthage + --use-xcframeworks).
        .binaryTarget(
            name: "MailCore",
            path: "Frameworks/MailCore.xcframework"
        ),
        .target(
            name: "HostMailCore",
            dependencies: ["MailCore"],
            path: "Sources/HostMailCore",
            resources: [
                .process("Storage/HostMailStore.xcdatamodeld")
            ]
        )
    ]
)
