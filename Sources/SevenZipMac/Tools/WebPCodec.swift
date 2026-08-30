import CoreGraphics
import Darwin
import Foundation

private typealias WebPEncodeRGBAFunction = @convention(c) (
    UnsafePointer<UInt8>?, Int32, Int32, Int32, Float,
    UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
) -> Int
private typealias WebPFreeFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void

enum WebPCodecError: LocalizedError {
    case libraryUnavailable(String)
    case renderingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let message): "WebP 编码组件不可用：\(message)"
        case .renderingFailed: "无法为 WebP 编码准备图片。"
        case .encodingFailed: "WebP 编码失败。"
        }
    }
}

final class WebPCodec: @unchecked Sendable {
    static let shared = WebPCodec()

    private let handle: UnsafeMutableRawPointer?
    private let encodeRGBA: WebPEncodeRGBAFunction?
    private let freeWebP: WebPFreeFunction?
    private let loadError: String

    init(libraryCandidates: [URL]? = nil) {
        var opened: UnsafeMutableRawPointer?
        var attempted: [String] = []
        for url in libraryCandidates ?? Self.libraryCandidates {
            attempted.append(url.path)
            if FileManager.default.fileExists(atPath: url.path),
               let candidate = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) {
                opened = candidate
                break
            }
        }
        handle = opened
        if let opened,
           let encodeSymbol = dlsym(opened, "WebPEncodeRGBA"),
           let freeSymbol = dlsym(opened, "WebPFree") {
            encodeRGBA = unsafeBitCast(encodeSymbol, to: WebPEncodeRGBAFunction.self)
            freeWebP = unsafeBitCast(freeSymbol, to: WebPFreeFunction.self)
            loadError = ""
        } else {
            encodeRGBA = nil
            freeWebP = nil
            loadError = attempted.joined(separator: "、")
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func encode(_ image: CGImage, quality: Double) throws -> Data {
        guard let encodeRGBA, let freeWebP else {
            throw WebPCodecError.libraryUnavailable(loadError)
        }
        let width = image.width
        let height = image.height
        let stride = width * 4
        var rgba = [UInt8](repeating: 0, count: stride * height)
        let rendered = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: stride,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                        CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw WebPCodecError.renderingFailed }
        Self.unpremultiplyAlpha(&rgba)

        var output: UnsafeMutablePointer<UInt8>?
        let size = rgba.withUnsafeBufferPointer { buffer in
            encodeRGBA(
                buffer.baseAddress,
                Int32(width),
                Int32(height),
                Int32(stride),
                Float(min(max(quality, 0.01), 1) * 100),
                &output
            )
        }
        guard size > 0, let output else { throw WebPCodecError.encodingFailed }
        defer { freeWebP(UnsafeMutableRawPointer(output)) }
        return Data(bytes: output, count: size)
    }

    private static func unpremultiplyAlpha(_ pixels: inout [UInt8]) {
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0, alpha < 255 else { continue }
            pixels[offset] = UInt8(min(255, Int(pixels[offset]) * 255 / alpha))
            pixels[offset + 1] = UInt8(min(255, Int(pixels[offset + 1]) * 255 / alpha))
            pixels[offset + 2] = UInt8(min(255, Int(pixels[offset + 2]) * 255 / alpha))
        }
    }

    private static var libraryCandidates: [URL] {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["WEBP_LIBRARY_PATH"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let frameworks = Bundle.main.privateFrameworksURL {
            candidates.append(frameworks.appendingPathComponent("libwebp.dylib"))
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/webp/libwebp.dylib")
        )
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/lib/libwebp.dylib"))
        candidates.append(URL(fileURLWithPath: "/usr/local/lib/libwebp.dylib"))
        return candidates
    }
}
