import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case keep = "保持原格式"
    case jpeg = "JPEG"
    case png = "PNG"
    case heic = "HEIC"

    var id: String { rawValue }

    func type(for source: CGImageSource) -> UTType? {
        switch self {
        case .keep:
            guard let identifier = CGImageSourceGetType(source) as String? else { return nil }
            return UTType(identifier)
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        }
    }

    var preferredExtension: String? {
        switch self {
        case .keep: nil
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }
}

struct ImageProcessingOptions: Sendable {
    let maximumWidth: Int
    let maximumHeight: Int
    let quality: Double
    let format: ImageOutputFormat
    let replaceOriginals: Bool
}

struct ImageProcessingResult: Identifiable, Equatable, Sendable {
    let source: URL
    let destination: URL
    let error: String?

    var id: String { source.path }
}

enum ImageProcessingError: LocalizedError {
    case unreadableImage(String)
    case unsupportedOutput(String)
    case destinationExists(String)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let path): "无法读取图片：\(path)"
        case .unsupportedOutput(let path): "不支持该图片的输出格式：\(path)"
        case .destinationExists(let path): "目标文件已存在：\(path)"
        case .encodingFailed(let path): "图片编码失败：\(path)"
        }
    }
}

enum ImageProcessingService {
    static let supportedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp"])

    static func imageFiles(in root: URL, recursively: Bool, fileManager: FileManager = .default) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = recursively
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard supportedExtensions.contains(url.pathExtension.lowercased()),
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files.append(url)
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func processDirectory(
        _ root: URL,
        outputRoot: URL?,
        recursively: Bool,
        options: ImageProcessingOptions,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) throws -> [ImageProcessingResult] {
        let files = try imageFiles(in: root, recursively: recursively)
        var results: [ImageProcessingResult] = []
        for (index, source) in files.enumerated() {
            defer { progress(index + 1, files.count, source.path) }
            do {
                let destination = try destinationURL(
                    for: source,
                    root: root,
                    outputRoot: outputRoot,
                    options: options
                )
                try process(source: source, destination: destination, options: options)
                results.append(ImageProcessingResult(source: source, destination: destination, error: nil))
            } catch {
                results.append(ImageProcessingResult(
                    source: source,
                    destination: source,
                    error: error.localizedDescription
                ))
            }
        }
        return results
    }

    static func process(source: URL, destination: URL, options: ImageProcessingOptions) throws {
        guard let sourceImage = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ImageProcessingError.unreadableImage(source.path)
        }
        guard let outputType = options.format.type(for: sourceImage) else {
            throw ImageProcessingError.unsupportedOutput(source.path)
        }
        let image = try renderedImage(from: sourceImage, options: options, path: source.path)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: temporary) }
        guard let output = CGImageDestinationCreateWithURL(temporary as CFURL, outputType.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.unsupportedOutput(destination.path)
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = min(max(options.quality, 0.01), 1.0)
        properties[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw ImageProcessingError.encodingFailed(destination.path)
        }

        if source.standardizedFileURL == destination.standardizedFileURL {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw ImageProcessingError.destinationExists(destination.path)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            if options.replaceOriginals { try fileManager.removeItem(at: source) }
        }
    }

    private static func renderedImage(
        from source: CGImageSource,
        options: ImageProcessingOptions,
        path: String
    ) throws -> CGImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        var ratio = 1.0
        if options.maximumWidth > 0, width > options.maximumWidth {
            ratio = min(ratio, Double(options.maximumWidth) / Double(width))
        }
        if options.maximumHeight > 0, height > options.maximumHeight {
            ratio = min(ratio, Double(options.maximumHeight) / Double(height))
        }
        let maximumPixel = max(1, Int(ceil(Double(max(width, height)) * ratio)))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageProcessingError.unreadableImage(path)
        }
        return image
    }

    private static func destinationURL(
        for source: URL,
        root: URL,
        outputRoot: URL?,
        options: ImageProcessingOptions
    ) throws -> URL {
        let relative = String(source.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base: URL
        if let outputRoot {
            base = outputRoot.appendingPathComponent(relative)
        } else if options.replaceOriginals {
            base = source
        } else {
            let stem = source.deletingPathExtension().lastPathComponent + "_converted"
            base = source.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension(source.pathExtension)
        }
        guard let ext = options.format.preferredExtension else { return base }
        return base.deletingPathExtension().appendingPathExtension(ext)
    }
}
