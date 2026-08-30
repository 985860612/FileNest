import AppKit
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import SevenZipMac

@Suite("Migrated file, image, PDF and spreadsheet tools")
struct ToolMigrationTests {
    @Test("File signatures are detected and missing extensions are repaired through preview")
    func extensionRepair() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("scan")
        try Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]).write(to: source)

        let preview = try FileToolService.extensionRepairPreview(in: root)
        #expect(preview.count == 1)
        #expect(preview[0].destination.lastPathComponent == "scan.pdf")
        #expect(preview[0].state == .ready)

        let (results, summary) = FileToolService.executeMoves(preview)
        #expect(results[0].state == .success)
        #expect(summary.succeeded == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("scan.pdf").path))

        let office = root.appendingPathComponent("workbook")
        try Data([0x50, 0x4B, 0x03, 0x04] + Array("xl/worksheets/sheet1.xml".utf8)).write(to: office)
        #expect(DetectedFileType.detect(at: office) == .xlsx)
    }

    @Test("Regex copy uses relative paths and rejects output traversal")
    func regexCopySafety() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let nested = root.appendingPathComponent("案件", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let source = nested.appendingPathComponent("证据.txt")
        try Data("内容".utf8).write(to: source)

        let preview = try FileToolService.regexCopyPreview(
            in: root,
            outputRoot: output,
            pattern: "案件/(.+)",
            replacement: "归档/$1"
        )
        #expect(preview.count == 1)
        #expect(preview[0].destination == output.appendingPathComponent("归档/证据.txt"))
        let (_, summary) = FileToolService.executeCopies(preview)
        #expect(summary.succeeded == 1)
        #expect(try String(contentsOf: output.appendingPathComponent("归档/证据.txt"), encoding: .utf8) == "内容")

        #expect(throws: FileToolError.self) {
            try FileToolService.regexCopyPreview(
                in: root,
                outputRoot: output,
                pattern: "(.+)",
                replacement: "../$1"
            )
        }
    }

    @Test("Name sanitizing preserves Chinese and marks duplicate destinations")
    func sanitizeNames() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("材料  一.pdf"))
        try Data().write(to: root.appendingPathComponent("材料@一.pdf"))

        let preview = try FileToolService.sanitizePreview(in: root)
        #expect(preview.count == 2)
        #expect(preview.allSatisfy { $0.destination.lastPathComponent == "材料_一.pdf" })
        #expect(preview.allSatisfy { $0.state == .invalid("目标路径重复") })
    }

    @Test("Image processing resizes and converts without deleting the source")
    func imageProcessing() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample.png")
        try writeImage(width: 120, height: 60, to: source)
        let options = ImageProcessingOptions(
            maximumWidth: 40,
            maximumHeight: 40,
            quality: 0.8,
            format: .jpeg,
            replaceOriginals: false
        )

        let results = try ImageProcessingService.processDirectory(
            root,
            outputRoot: nil,
            recursively: false,
            options: options
        )
        #expect(results.count == 1)
        #expect(results[0].error == nil)
        #expect(results[0].destination.lastPathComponent == "sample_converted.jpg")
        #expect(FileManager.default.fileExists(atPath: source.path))
        guard let imageSource = CGImageSourceCreateWithURL(results[0].destination as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            Issue.record("无法读取输出图片")
            return
        }
        #expect((properties[kCGImagePropertyPixelWidth] as? Int) == 40)
        #expect((properties[kCGImagePropertyPixelHeight] as? Int) == 20)

        let webp = root.appendingPathComponent("sample.webp")
        try ImageProcessingService.process(
            source: source,
            destination: webp,
            options: ImageProcessingOptions(
                maximumWidth: 30,
                maximumHeight: 30,
                quality: 0.75,
                format: .webp,
                replaceOriginals: false
            )
        )
        let webpData = try Data(contentsOf: webp)
        #expect(String(decoding: webpData.prefix(4), as: UTF8.self) == "RIFF")
        guard let webpSource = CGImageSourceCreateWithURL(webp as CFURL, nil),
              let webpProperties = CGImageSourceCopyPropertiesAtIndex(webpSource, 0, nil) as? [CFString: Any] else {
            Issue.record("无法读取 WebP 输出")
            return
        }
        #expect((webpProperties[kCGImagePropertyPixelWidth] as? Int) == 30)
        #expect((webpProperties[kCGImagePropertyPixelHeight] as? Int) == 15)
    }

    @Test("Enhanced catalog includes directories, metadata and detected type")
    func enhancedCatalog() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("子目录", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: folder.appendingPathComponent("图片.png"))

        let entries = try FileCatalogService.scan(directory: root, recursively: true, includeDirectories: true)
        #expect(entries.count == 2)
        #expect(entries.contains { $0.isDirectory && $0.fileName == "子目录" })
        let image = try #require(entries.first { !$0.isDirectory })
        #expect(image.detectedExtension == "png")
        #expect(image.parentDirectoryName == "子目录")
        #expect(image.spreadsheetRow.count == FileCatalogService.spreadsheetHeaders.count)
    }

    @Test("Images become PDFs and PDF merge preserves every page")
    func imageToPDFAndMerge() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeImage(width: 20, height: 30, to: root.appendingPathComponent("01.png"))
        try writeImage(width: 30, height: 20, to: root.appendingPathComponent("02.png"))
        let converted = try PDFToolService.convertImagesToPDF(in: root, outputRoot: nil, recursively: false)
        #expect(converted.count == 2)
        #expect(converted.allSatisfy { $0.error == nil })

        let pdfs = converted.compactMap(\.destination)
        let merged = root.appendingPathComponent("merged.pdf")
        try PDFToolService.merge(files: pdfs, to: merged)
        #expect(PDFDocument(url: merged)?.pageCount == 2)
        #expect(throws: PDFToolError.self) { try PDFToolService.merge(files: pdfs, to: merged) }

        let batch = root.appendingPathComponent("案件一", isDirectory: true)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        try writeImage(width: 10, height: 10, to: batch.appendingPathComponent("01_材料.png"))
        try writeImage(width: 10, height: 10, to: batch.appendingPathComponent("99_判决书.png"))
        let preview = try PDFToolService.batchMergePreview(root: root, sortConfiguration: "判决书:1\n材料:2")
        #expect(preview.map { $0.file.lastPathComponent } == ["99_判决书.png", "01_材料.png"])
    }

    @Test("PDF keyword splitting and regex extraction work on text PDFs")
    func splitAndExtractPDFText() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("document.pdf")
        try writeTextPDF(["START 编号 A001", "正文", "START 编号 B002"], to: source)

        let outputs = try PDFToolService.splitPDF(source, keyword: "START", outputRoot: root)
        #expect(outputs.count == 2)
        #expect(PDFDocument(url: outputs[0])?.pageCount == 2)
        #expect(PDFDocument(url: outputs[1])?.pageCount == 1)

        let rows = try PDFToolService.extractRegex(from: [source], pattern: "编号\\s+([A-Z]\\d{3})")
        #expect(rows.map(\.value) == ["A001", "B002"])
    }

    @Test("Spreadsheet grouping preserves first-seen group order and de-duplicates values")
    func spreadsheetGrouping() throws {
        let group = XLSXColumn(index: 0, title: "案件")
        let person = XLSXColumn(index: 1, title: "人员")
        let status = XLSXColumn(index: 2, title: "状态")
        let sheet = XLSXSheet(
            columns: [group, person, status],
            rows: [
                ["B", "张三", "完成"],
                ["A", "李四", "待办"],
                ["B", "张三", "归档"],
                ["B", "王五", "完成"]
            ]
        )
        let rows = try SpreadsheetToolService.groupedRows(sheet: sheet, groupingColumn: group)
        #expect(rows == [
            ["B", "张三,王五", "完成,归档"],
            ["A", "李四", "待办"]
        ])
    }

    private func writeImage(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func writeTextPDF(_ pages: [String], to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 500)
        let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for text in pages {
            context.beginPDFPage(nil)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            NSString(string: text).draw(
                at: CGPoint(x: 40, y: 420),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
