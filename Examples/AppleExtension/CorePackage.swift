// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MYCODEXCore",
    platforms: [.iOS(.v16)],
    products: [.library(name: "MYCODEX", targets: ["MYCODEX"])],
    targets: [
        .binaryTarget(name: "COpenVPNBridge", path: "COpenVPNBridge.xcframework"),
        .target(name: "MYCODEX", dependencies: ["COpenVPNBridge"],
                linkerSettings: [
                    .linkedLibrary("c++"),
                    .linkedFramework("Security"),
                    .linkedFramework("SystemConfiguration"),
                    .linkedFramework("UIKit")
                ])
    ]
)
