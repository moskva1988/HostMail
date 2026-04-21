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
    dependencies: [
        // MailCore2 — SPM-compatible fork. If this URL fails to resolve on Mac,
        // replace with another maintained SPM fork of MailCore/mailcore2.
        .package(url: "https://github.com/dinhquan/MailCore2", branch: "master")
    ],
    targets: [
        .target(
            name: "HostMailCore",
            dependencies: [
                .product(name: "MailCore", package: "MailCore2")
            ],
            path: "Sources/HostMailCore",
            resources: [
                .process("Storage/HostMailStore.xcdatamodeld")
            ]
        )
    ]
)
