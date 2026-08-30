import AppKit
import Foundation
import PDFKit

struct PDFExtractionRow: Identifiable, Equatable, Sendable {
    let filePath: String
    let fileName: String
    let value: String

    var id: String { "\(filePath)\u{0}\(value)" }

    var spreadsheetRow: [String] { [filePath, fileName, value] }
}

struct PDFBatchResult: Identifiable, Equatable, Sendable {
    let source: URL
    let destination: URL?
    let error: String?

    var id: String { source.path }
}

struct PDFMergePreviewEntry: Identifiable, Equatable, Sendable {
    let directory: URL
    let file: URL
    let order: Int

    var id: String { file.path }
}

enum PDFToolError: LocalizedError {
    case noSupportedFiles(String)
    case unreadablePDF(String)
    case unreadableImage(String)
    case invalidRegularExpression(String)
    case keywordNotFound(String)
    case destinationExists(String)
    case outputFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSupportedFiles(let path): "没有找到可处理的 PDF 或图片：\(path)"
        case .unreadablePDF(let path): "无法读取 PDF：\(path)"
        case .unreadableImage(let path): "无法读取图片：\(path)"
        case .invalidRegularExpression(let message): "正则表达式无效：\(message)"
        case .keywordNotFound(let path): "PDF 中未找到拆分关键字：\(path)"
        case .destinationExists(let path): "目标文件已存在：\(path)"
        case .outputFailed(let path): "无法写入 PDF：\(path)"
        }
    }
}

enum PDFToolService {
    static let pdfAndImageExtensions = Set(["pdf", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp"])

    static func convertImagesToPDF(
        in root: URL,
        outputRoot: URL?,
        recursively: Bool,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) throws -> [PDFBatchResult] {
        let images = try ImageProcessingService.imageFiles(in: root, recursively: recursively)
        var results: [PDFBatchResult] = []
        for (index, source) in images.enumerated() {
            defer { progress(index + 1, images.count, source.path) }
            let destination = mirroredDestination(
                for: source,
                root: root,
                outputRoot: outputRoot,
                extension: "pdf"
            )
            do {
                let document = PDFDocument()
                guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else {
                    throw PDFToolError.unreadableImage(source.path)
                }
                document.insert(page, at: 0)
                try write(document, to: destination)
                results.append(PDFBatchResult(source: source, destination: destination, error: nil))
            } catch {
                results.append(PDFBatchResult(source: source, destination: destination, error: error.localizedDescription))
            }
        }
        return results
    }

    static func batchMergeChildDirectories(
        root: URL,
        outputRoot: URL?,
        sortConfiguration: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) throws -> [PDFBatchResult] {
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var results: [PDFBatchResult] = []
        for (index, directory) in directories.enumerated() {
            defer { progress(index + 1, directories.count, directory.path) }
            let destination = (outputRoot ?? root)
                .appendingPathComponent(directory.lastPathComponent)
                .appendingPathExtension("pdf")
            do {
                let files = try mergeableFiles(in: directory, sortConfiguration: sortConfiguration)
                guard !files.isEmpty else { throw PDFToolError.noSupportedFiles(directory.path) }
                try merge(files: files, to: destination)
                results.append(PDFBatchResult(source: directory, destination: destination, error: nil))
            } catch {
                results.append(PDFBatchResult(source: directory, destination: destination, error: error.localizedDescription))
            }
        }
        return results
    }

    static func batchMergePreview(root: URL, sortConfiguration: String) throws -> [PDFMergePreviewEntry] {
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return try directories.flatMap { directory in
            try mergeableFiles(in: directory, sortConfiguration: sortConfiguration).enumerated().map { offset, file in
                PDFMergePreviewEntry(directory: directory, file: file, order: offset + 1)
            }
        }
    }

    static func mergeableFiles(in directory: URL, sortConfiguration: String) throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            pdfAndImageExtensions.contains($0.pathExtension.lowercased()) &&
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        let priorities = parseSortConfiguration(sortConfiguration)
        return files.sorted { lhs, rhs in
            let leftPriority = keywordPriority(lhs.lastPathComponent, priorities: priorities)
            let rightPriority = keywordPriority(rhs.lastPathComponent, priorities: priorities)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    static func merge(files: [URL], to destination: URL) throws {
        let output = PDFDocument()
        for file in files {
            if file.pathExtension.lowercased() == "pdf" {
                guard let input = PDFDocument(url: file) else { throw PDFToolError.unreadablePDF(file.path) }
                for pageIndex in 0..<input.pageCount {
                    if let page = input.page(at: pageIndex) { output.insert(page, at: output.pageCount) }
                }
            } else {
                guard let image = NSImage(contentsOf: file), let page = PDFPage(image: image) else {
                    throw PDFToolError.unreadableImage(file.path)
                }
                output.insert(page, at: output.pageCount)
            }
        }
        guard output.pageCount > 0 else { throw PDFToolError.noSupportedFiles(destination.path) }
        try write(output, to: destination)
    }

    static func splitPDF(_ source: URL, keyword: String, outputRoot: URL) throws -> [URL] {
        guard let input = PDFDocument(url: source) else { throw PDFToolError.unreadablePDF(source.path) }
        var chunks: [[PDFPage]] = []
        var current: [PDFPage] = []
        var found = false
        for index in 0..<input.pageCount {
            guard let page = input.page(at: index) else { continue }
            let beginsChunk = page.string?.localizedCaseInsensitiveContains(keyword) == true
            if beginsChunk {
                found = true
                if !current.isEmpty { chunks.append(current); current = [] }
            }
            if found { current.append(page) }
        }
        if !current.isEmpty { chunks.append(current) }
        guard found, !chunks.isEmpty else { throw PDFToolError.keywordNotFound(source.path) }
        let folder = outputRoot.appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var outputs: [URL] = []
        let destinations = chunks.indices.map {
            folder.appendingPathComponent(String(format: "%03d.pdf", $0 + 1))
        }
        if let existing = destinations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw PDFToolError.destinationExists(existing.path)
        }
        for (offset, pages) in chunks.enumerated() {
            let document = PDFDocument()
            for page in pages { document.insert(page, at: document.pageCount) }
            let destination = destinations[offset]
            try write(document, to: destination)
            outputs.append(destination)
        }
        return outputs
    }

    static func extractRegex(
        from files: [URL],
        pattern: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) throws -> [PDFExtractionRow] {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            throw PDFToolError.invalidRegularExpression(error.localizedDescription)
        }
        var rows: [PDFExtractionRow] = []
        for (index, file) in files.enumerated() {
            defer { progress(index + 1, files.count, file.path) }
            guard let document = PDFDocument(url: file) else { throw PDFToolError.unreadablePDF(file.path) }
            let text = document.string ?? ""
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                let selectedRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard selectedRange.location != NSNotFound, let swiftRange = Range(selectedRange, in: text) else { continue }
                rows.append(PDFExtractionRow(
                    filePath: file.path,
                    fileName: file.lastPathComponent,
                    value: String(text[swiftRange])
                ))
            }
        }
        return rows
    }

    static func pdfFiles(in root: URL, recursively: Bool) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = recursively
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "pdf" {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(url) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func write(_ document: PDFDocument, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PDFToolError.destinationExists(destination.path)
        }
        guard let data = document.dataRepresentation() else { throw PDFToolError.outputFailed(destination.path) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    private static func mirroredDestination(
        for source: URL,
        root: URL,
        outputRoot: URL?,
        extension outputExtension: String
    ) -> URL {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let relative = sourcePath.hasPrefix(rootPath + "/")
            ? String(sourcePath.dropFirst(rootPath.count + 1))
            : source.lastPathComponent
        return (outputRoot?.appendingPathComponent(relative) ?? source)
            .deletingPathExtension().appendingPathExtension(outputExtension)
    }

    private static func parseSortConfiguration(_ configuration: String) -> [(String, Int)] {
        configuration.split(whereSeparator: \Character.isNewline).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let priority = Int(parts[1]), !parts[0].isEmpty else { return nil }
            return (parts[0], priority)
        }
    }

    private static func keywordPriority(_ name: String, priorities: [(String, Int)]) -> Int {
        priorities.first(where: { name.localizedCaseInsensitiveContains($0.0) })?.1 ?? Int.max
    }
}
