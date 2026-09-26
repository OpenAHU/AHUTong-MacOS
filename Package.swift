// swift-tools-version: 6.0
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "AHUTongMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AHUTongMac", targets: ["AHUTongMac"])
    ],
    targets: [
        .executableTarget(
            name: "AHUTongMac",
            linkerSettings: [
                .unsafeFlags(["-L\(packageRoot)/Libraries", "-lahutong_rs"]),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreFoundation"),
                .linkedLibrary("iconv"),
                .linkedLibrary("resolv")
            ]
        ),
        .testTarget(
            name: "AHUTongMacTests",
            dependencies: ["AHUTongMac"]
        )
    ]
)
