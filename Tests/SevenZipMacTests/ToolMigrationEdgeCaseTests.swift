import AppKit
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import FileNestKit

@Suite("Migrated tool edge cases and end-to-end output")
struct ToolMigrationEdgeCaseTests {
    @Test("Extension repair detects every supported signature and refuses collisions")
    func extensionRepairSignaturesAndCollision() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures: [(String, [UInt8], DetectedFileType)] = [
            ("jpeg", [0xFF, 0xD8, 0xFF], .jpeg),
            ("png", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], .png),
            ("gif", Array("GIF89a".utf8), .gif),
            ("tiff", [0x49, 0x49, 0x2A, 0x00], .tiff),
            ("bmp", [0x42, 0x4D], .bmp),
            ("pdf", Array("%PDF-1.7".utf8), .pdf),
            ("rar", [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], .rar),
            ("7z", [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], .sevenZip),
            ("gzip", [0x1F, 0x8B], .gzip),
            ("bzip2", Array("BZh".utf8), .bzip2),
            ("xz", [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00], .xz)
        ]
        for (name, bytes, expected) in fixtures {
            let file = root.appendingPathComponent(name)
            try Data(bytes).write(to: file)
            #expect(DetectedFileType.detect(at: file) == expected)
        }
        let collision = root.appendingPathComponent("pdf.pdf")
        try Data().write(to: collision)

        let preview = try FileToolService.extensionRepairPreview(in: root)
        #expect(preview.count == fixtures.count)
        #expect(preview.first { $0.source.lastPathComponent == "pdf" }?.state == .invalid("目标已存在"))
    }

    @Test("Regex copy reports invalid expressions, unchanged paths and duplicate destinations")
    func regexCopyValidation() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        try Data("A".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("B".utf8).write(to: root.appendingPathComponent("b.txt"))

        #expect(throws: FileToolError.self) {
            try FileToolService.regexCopyPreview(in: root, outputRoot: output, pattern: "[", replacement: "x")
        }
        let duplicates = try FileToolService.regexCopyPreview(
            in: root,
            outputRoot: output,
            pattern: "[ab]\\.txt",
            replacement: "same.txt"
        )
        #expect(duplicates.count == 2)
        #expect(duplicates.allSatisfy { $0.state == .invalid("目标路径重复") })

        let unchanged = try FileToolService.regexCopyPreview(
            in: root,
            outputRoot: root,
            pattern: "(.+)",
            replacement: "$1"
        )
        #expect(unchanged.allSatisfy { $0.state == .invalid("源和目标相同") })
    }

    @Test("Nested name cleanup moves children before their renamed parent")
    func nestedNameCleanup() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("案件  一", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("证据".utf8).write(to: folder.appendingPathComponent("材料  一.txt"))

        let preview = try FileToolService.sanitizePreview(in: root)
        #expect(preview.count == 2)
        #expect(preview[0].source.lastPathComponent == "材料  一.txt")
        let (results, summary) = FileToolService.executeMoves(preview)
        #expect(summary.succeeded == 2)
        #expect(results.allSatisfy { $0.state == .success })
        let cleaned = root.appendingPathComponent("案件_一/材料_一.txt")
        #expect(try String(contentsOf: cleaned, encoding: .utf8) == "证据")
    }

    @Test("Image discovery respects recursion and processing handles replacement and corrupt input")
    func imageDiscoveryReplacementAndFailure() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let top = root.appendingPathComponent("top.png")
        let child = nested.appendingPathComponent("child.png")
        try writeImage(width: 80, height: 40, to: top)
        try writeImage(width: 20, height: 10, to: child)
        try Data("not an image".utf8).write(to: root.appendingPathComponent("broken.png"))

        #expect(try ImageProcessingService.imageFiles(in: root, recursively: false).count == 2)
        #expect(try ImageProcessingService.imageFiles(in: root, recursively: true).count == 3)
        let results = try ImageProcessingService.processDirectory(
            root,
            outputRoot: output,
            recursively: true,
            options: ImageProcessingOptions(
                maximumWidth: 0,
                maximumHeight: 0,
                quality: 0.9,
                format: .jpeg,
                replaceOriginals: true
            )
        )
        #expect(results.count == 3)
        #expect(results.filter { $0.error == nil }.count == 2)
        #expect(results.filter { $0.error != nil }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: top.path))
        #expect(!FileManager.default.fileExists(atPath: child.path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("top.jpg").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("nested/child.jpg").path))
    }

    @Test("Image output refuses an existing destination")
    func imageDestinationCollision() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png")
        let destination = root.appendingPathComponent("result.jpg")
        try writeImage(width: 10, height: 10, to: source)
        try Data("keep".utf8).write(to: destination)

        #expect(throws: ImageProcessingError.self) {
            try ImageProcessingService.process(
                source: source,
                destination: destination,
                options: ImageProcessingOptions(
                    maximumWidth: 0,
                    maximumHeight: 0,
                    quality: 0.8,
                    format: .jpeg,
                    replaceOriginals: false
                )
            )
        }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "keep")
    }

    @Test("WebP reports a clear error when its encoder library is unavailable")
    func webPLibraryUnavailable() throws {
        let image = try makeImage(width: 4, height: 4)
        let codec = WebPCodec(libraryCandidates: [])
        #expect(throws: WebPCodecError.self) { try codec.encode(image, quality: 0.8) }
    }

    @Test("Batch PDF merge writes one ordered document per child directory")
    func batchPDFMergeEndToEnd() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let caseA = root.appendingPathComponent("案件A", isDirectory: true)
        let caseB = root.appendingPathComponent("案件B", isDirectory: true)
        let empty = root.appendingPathComponent("空目录", isDirectory: true)
        for directory in [caseA, caseB, empty] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try writeTextPDF(["MATERIAL"], to: caseA.appendingPathComponent("02_材料.pdf"))
        try writeTextPDF(["JUDGMENT"], to: caseA.appendingPathComponent("01_判决书.pdf"))
        try writeImage(width: 12, height: 12, to: caseB.appendingPathComponent("证据.png"))

        let results = try PDFToolService.batchMergeChildDirectories(
            root: root,
            outputRoot: output,
            sortConfiguration: "判决书:1\n材料:2"
        )
        #expect(results.count == 3)
        #expect(results.filter { $0.error == nil }.count == 2)
        #expect(results.first { $0.source.lastPathComponent == empty.lastPathComponent }?.error != nil)
        let mergedA = try #require(PDFDocument(url: output.appendingPathComponent("案件A.pdf")))
        #expect(mergedA.pageCount == 2)
        #expect(mergedA.page(at: 0)?.string?.contains("JUDGMENT") == true)
        #expect(mergedA.page(at: 1)?.string?.contains("MATERIAL") == true)
        #expect(PDFDocument(url: output.appendingPathComponent("案件B.pdf"))?.pageCount == 1)
    }

    @Test("PDF tools reject invalid input and discover files at the requested depth")
    func pdfValidationAndDiscovery() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let top = root.appendingPathComponent("top.pdf")
        let child = nested.appendingPathComponent("child.PDF")
        try writeTextPDF(["普通正文"], to: top)
        try writeTextPDF(["编号 C003"], to: child)

        #expect(try PDFToolService.pdfFiles(in: root, recursively: false).map(\.lastPathComponent) == ["top.pdf"])
        #expect(try PDFToolService.pdfFiles(in: root, recursively: true).count == 2)
        #expect(throws: PDFToolError.self) {
            try PDFToolService.extractRegex(from: [top], pattern: "[")
        }
        #expect(throws: PDFToolError.self) {
            try PDFToolService.splitPDF(top, keyword: "START", outputRoot: root)
        }
        #expect(throws: PDFToolError.self) {
            try PDFToolService.merge(files: [], to: root.appendingPathComponent("empty.pdf"))
        }

        try writeImage(width: 10, height: 10, to: nested.appendingPathComponent("image.png"))
        let output = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let converted = try PDFToolService.convertImagesToPDF(in: root, outputRoot: output, recursively: true)
        #expect(converted.count == 1)
        #expect(converted[0].error == nil)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("nested/image.pdf").path))
    }

    @Test("Spreadsheet grouping validates the column and ignores blank duplicate values")
    func spreadsheetGroupingValidation() throws {
        let group = XLSXColumn(index: 0, title: "案件")
        let value = XLSXColumn(index: 1, title: "人员")
        let sheet = XLSXSheet(
            columns: [group, value],
            rows: [["A", " 张三 "], ["A", ""], ["A", "张三"], ["A", "李四"]]
        )
        #expect(try SpreadsheetToolService.groupedRows(sheet: sheet, groupingColumn: group) == [["A", "张三,李四"]])
        #expect(throws: SpreadsheetToolError.self) {
            try SpreadsheetToolService.groupedRows(
                sheet: sheet,
                groupingColumn: XLSXColumn(index: 9, title: "不存在")
            )
        }
    }

    @Test(
        "Catalog, PDF extraction and grouped rows survive XLSX write/read round trips",
        .enabled(if: ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_INTEGRATION"] == "1")
    )
    func migratedXLSXEndToEnd() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try Data("内容".utf8).write(to: input.appendingPathComponent("材料.txt"))

        let catalogWorkbook = root.appendingPathComponent("catalog.xlsx")
        let entries = try FileCatalogService.export(directory: input, to: catalogWorkbook)
        let catalog = try XLSXDocument.read(from: catalogWorkbook)
        #expect(entries.count == 1)
        #expect(catalog.columns.map(\.title) == FileCatalogService.spreadsheetHeaders)
        #expect(catalog.rows.count == 1)
        #expect(catalog.rows[0][3] == "材料")

        let pdf = root.appendingPathComponent("source.pdf")
        try writeTextPDF(["编号 A001", "编号 B002"], to: pdf)
        let extracted = try PDFToolService.extractRegex(from: [pdf], pattern: "编号\\s+([A-Z]\\d{3})")
        let extractionWorkbook = root.appendingPathComponent("extraction.xlsx")
        try XLSXDocument.write(
            headers: ["文件路径", "文件名", "提取内容"],
            rows: extracted.map(\.spreadsheetRow),
            to: extractionWorkbook
        )
        let extractionSheet = try XLSXDocument.read(from: extractionWorkbook)
        #expect(extractionSheet.rows.map { $0[2] } == ["A001", "B002"])

        let groupColumn = XLSXColumn(index: 0, title: "案件")
        let sourceSheet = XLSXSheet(
            columns: [groupColumn, XLSXColumn(index: 1, title: "人员")],
            rows: [["A", "张三"], ["A", "李四"]]
        )
        let grouped = try SpreadsheetToolService.groupedRows(sheet: sourceSheet, groupingColumn: groupColumn)
        let groupedWorkbook = root.appendingPathComponent("grouped.xlsx")
        try XLSXDocument.write(headers: sourceSheet.columns.map(\.title), rows: grouped, to: groupedWorkbook)
        let groupedSheet = try XLSXDocument.read(from: groupedWorkbook)
        #expect(groupedSheet.rows == [["A", "张三,李四"]])
    }

    private func writeImage(width: Int, height: Int, to url: URL) throws {
        let image = try makeImage(width: width, height: height)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return image
    }

    private func writeTextPDF(_ pages: [String], to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 500)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SevenZipMac-ToolEdgeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
