// swift-tools-version: 6.0
import PackageDescription
import Foundation

let paddleOCRDependency: Package.Dependency
if let localPath = ProcessInfo.processInfo.environment["PADDLEOCR_COREML_LOCAL_PATH"] {
    paddleOCRDependency = .package(path: localPath)
} else {
    paddleOCRDependency = .package(
        url: "https://github.com/985860612/PaddleOCRCoreML.git",
        exact: "0.3.1"
    )
}

let package = Package(
    name: "FileNest",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SevenZipMac", targets: ["SevenZipMac"]),
        .executable(name: "filenest-cli", targets: ["FileNestCLI"]),
        .executable(name: "filenest-mcp", targets: ["FileNestMCP"]),
        .library(name: "FileNestKit", targets: ["FileNestKit"]),
        .library(name: "FileNestOCRCore", targets: ["FileNestOCRCore"])
    ],
    dependencies: [paddleOCRDependency],
    targets: [
        .executableTarget(
            name: "SevenZipMac",
            dependencies: ["FileNestKit"],
            path: "Sources/FileNestApp"
        ),
        .target(
            name: "FileNestKit",
            dependencies: [
                "FileNestOCRCore",
            ],
            path: "Sources/SevenZipMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "FileNestOCRCore",
            dependencies: [
                .product(name: "PaddleOCRCoreML", package: "PaddleOCRCoreML")
            ],
            path: "Sources/FileNestOCRCore"
        ),
        .executableTarget(
            name: "FileNestCLI",
            dependencies: [
                "FileNestKit",
                "FileNestOCRCore",
                .product(name: "PaddleOCRCoreML", package: "PaddleOCRCoreML")
            ],
            path: "Sources/FileNestCLI"
        ),
        .executableTarget(
            name: "FileNestMCP",
            dependencies: ["FileNestKit", "FileNestOCRCore"],
            path: "Sources/FileNestMCP"
        ),
        .testTarget(
            name: "SevenZipMacTests",
            dependencies: ["FileNestKit", "FileNestOCRCore"],
            path: "Tests/SevenZipMacTests"
        )
    ]
)
