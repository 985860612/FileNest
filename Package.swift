// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileNest",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SevenZipMac", targets: ["SevenZipMac"])
    ],
    targets: [
        .executableTarget(
            name: "SevenZipMac",
            path: "Sources/SevenZipMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("ImageIO")
            ]
        ),
        .testTarget(
            name: "SevenZipMacTests",
            dependencies: ["SevenZipMac"],
            path: "Tests/SevenZipMacTests"
        )
    ]
)
