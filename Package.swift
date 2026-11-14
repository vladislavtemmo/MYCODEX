// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MYCODEX",
    // Предварительные минимальные версии. Проверить в Xcode на Apple-устройствах.
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MYCODEX", targets: ["MYCODEX"]),
        .library(name: "MYCODEXConfiguration", targets: ["MYCODEXConfiguration"])
    ],
    targets: [
        .target(
            name: "COpenVPNBridge",
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath("include")]
        ),
        .target(name: "MYCODEX", dependencies: ["COpenVPNBridge"]),
        .target(name: "MYCODEXConfiguration", dependencies: ["MYCODEX"]),
        .testTarget(name: "MYCODEXTests", dependencies: ["MYCODEX"]),
        .testTarget(name: "MYCODEXConfigurationTests", dependencies: ["MYCODEX", "MYCODEXConfiguration"])
    ],
    cxxLanguageStandard: .cxx20
)
