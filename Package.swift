// swift-tools-version: 6.0
import PackageDescription
import Foundation

let paddleOCRDependency: Package.Dependency
if let localPath = ProcessInfo.processInfo.environment["PADDLEOCR_COREML_LOCAL_PATH"] {
    paddleOCRDependency = .package(path: localPath)
} else {
    paddleOCRDependency = .package(
        url: "https://github.com/985860612/PaddleOCRCoreML.git",
        from: "0.1.0"
    )
}

let package = Package(
    name: "FileNest",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SevenZipMac", targets: ["SevenZipMac"])
    ],
    dependencies: [paddleOCRDependency],
    targets: [
        .executableTarget(
            name: "SevenZipMac",
            dependencies: [
                .product(name: "PaddleOCRCoreML", package: "PaddleOCRCoreML")
            ],
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
