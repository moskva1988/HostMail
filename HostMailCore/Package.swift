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
        // SPIKE: SwiftMail (pure Swift IMAP/SMTP, BSD-2). Validating it as a
        // replacement for the broken MailCore2 path on Apple Silicon macOS.
        // Range starts at 1.0.0 because 1.5.2 transitively requires
        // swift-dotenv 2.1.0 which needs swift-tools-version 6.0 (Xcode 16+).
        // SPM will pick the highest version compatible with our Swift 5.10
        // toolchain (Xcode 15.4). Tighten this once we're on Xcode 16.
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
