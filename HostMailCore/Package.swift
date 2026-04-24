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
        // Pure-Swift IMAP/SMTP (BSD-2). Replaces MailCore2 — works on
        // Apple Silicon macOS without Carthage / pre-built static libs.
        // Range starts at 1.0.0 to avoid swift-dotenv 2.1.0 (Swift 6) on
        // pre-Xcode-16 toolchains; once we drop Xcode 15 support raise to 1.5.2+.
        .package(url: "https://github.com/Cocoanetics/SwiftMail", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "HostMailCore",
            dependencies: [
                .product(name: "SwiftMail", package: "SwiftMail")
            ],
            path: "Sources/HostMailCore",
            resources: [
                .process("Storage/HostMailStore.xcdatamodeld")
            ]
        )
    ]
)
