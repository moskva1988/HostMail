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
        .package(url: "https://github.com/Cocoanetics/SwiftMail", from: "1.5.2")
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
