// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MYCODEX",
    // Provisional package floor for the Swift-only foundation. Final Apple
    // platform minimums must be validated with the tunnel extension on Xcode.
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MYCODEX", targets: ["MYCODEX"]),
        .library(name: "MYCODEXConfiguration", targets: ["MYCODEXConfiguration"])
    ],
    targets: [
        .target(name: "MYCODEX"),
        .target(name: "MYCODEXConfiguration", dependencies: ["MYCODEX"]),
        .testTarget(name: "MYCODEXTests", dependencies: ["MYCODEX"]),
        .testTarget(name: "MYCODEXConfigurationTests", dependencies: ["MYCODEX", "MYCODEXConfiguration"])
    ]
)
