// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SevenZipMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SevenZipMac", targets: ["SevenZipMac"])
    ],
    targets: [
        .executableTarget(
            name: "SevenZipMac",
            path: "Sources/SevenZipMac",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "SevenZipMacTests",
            dependencies: ["SevenZipMac"],
            path: "Tests/SevenZipMacTests"
        )
    ]
)

