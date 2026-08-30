import Foundation

enum DetectedFileType: String, CaseIterable, Sendable {
    case jpeg = "jpg"
    case png
    case gif
    case tiff = "tif"
    case bmp
    case pdf
    case zip
    case docx
    case xlsx
    case pptx
    case rar
    case sevenZip = "7z"
    case gzip = "gz"
    case bzip2 = "bz2"
    case xz

    static func detect(at url: URL) -> DetectedFileType? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), !header.isEmpty else { return nil }
        let bytes = [UInt8](header)
        func starts(_ signature: [UInt8]) -> Bool {
            bytes.count >= signature.count && Array(bytes.prefix(signature.count)) == signature
        }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return .gif }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if starts([0x42, 0x4D]) { return .bmp }
        if starts(Array("%PDF-".utf8)) { return .pdf }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) {
            try? handle.seek(toOffset: 0)
            let archiveData = (try? handle.read(upToCount: 1_048_576)) ?? header
            let archiveIndex = String(decoding: archiveData, as: UTF8.self)
            if archiveIndex.contains("word/") { return .docx }
            if archiveIndex.contains("xl/") { return .xlsx }
            if archiveIndex.contains("ppt/") { return .pptx }
            return .zip
        }
        if starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return .rar }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        if starts([0x1F, 0x8B]) { return .gzip }
        if starts(Array("BZh".utf8)) { return .bzip2 }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        return nil
    }
}

struct BatchFileOperation: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: URL
    let destination: URL
    let isDirectory: Bool
    var state: FileOperationState

    init(source: URL, destination: URL, isDirectory: Bool = false, state: FileOperationState) {
        id = UUID()
        self.source = source
        self.destination = destination
        self.isDirectory = isDirectory
        self.state = state
    }
}

enum FileToolError: LocalizedError {
    case invalidRegularExpression(String)
    case outputEscapesDestination(String)

    var errorDescription: String? {
        switch self {
        case .invalidRegularExpression(let message): "正则表达式无效：\(message)"
        case .outputEscapesDestination(let path): "替换后的路径超出输出目录：\(path)"
        }
    }
}

enum FileToolService {
    static func extensionRepairPreview(in root: URL, fileManager: FileManager = .default) throws -> [BatchFileOperation] {
        try regularFiles(in: root, fileManager: fileManager).compactMap { url in
            guard url.pathExtension.isEmpty, let type = DetectedFileType.detect(at: url) else { return nil }
            let destination = url.appendingPathExtension(type.rawValue)
            return BatchFileOperation(
                source: url,
                destination: destination,
                state: fileManager.fileExists(atPath: destination.path) ? .invalid("目标已存在") : .ready
            )
        }
    }

    static func regexCopyPreview(
        in root: URL,
        outputRoot: URL,
        pattern: String,
        replacement: String,
        fileManager: FileManager = .default
    ) throws -> [BatchFileOperation] {
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            throw FileToolError.invalidRegularExpression(error.localizedDescription)
        }
        let rootPath = root.standardizedFileURL.path
        let outputPath = outputRoot.standardizedFileURL.path
        let operations: [BatchFileOperation] = try regularFiles(in: root, fileManager: fileManager).compactMap { source in
            let relative = String(source.standardizedFileURL.path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let range = NSRange(relative.startIndex..<relative.endIndex, in: relative)
            guard expression.firstMatch(in: relative, range: range) != nil else { return nil }
            let replaced = expression.stringByReplacingMatches(in: relative, range: range, withTemplate: replacement)
            let destination = outputRoot.appendingPathComponent(replaced).standardizedFileURL
            guard destination.path == outputPath || destination.path.hasPrefix(outputPath + "/") else {
                throw FileToolError.outputEscapesDestination(replaced)
            }
            let unchanged = source.standardizedFileURL == destination
            let state: FileOperationState = unchanged
                ? .invalid("源和目标相同")
                : (fileManager.fileExists(atPath: destination.path) ? .invalid("目标已存在") : .ready)
            return BatchFileOperation(source: source, destination: destination, state: state)
        }
        return invalidatingDuplicateDestinations(operations)
    }

    static func sanitizePreview(in root: URL, fileManager: FileManager = .default) throws -> [BatchFileOperation] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var operations: [BatchFileOperation] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true || values.isRegularFile == true else { continue }
            let isDirectory = values.isDirectory == true
            let originalName = url.lastPathComponent
            let stem = isDirectory ? originalName : url.deletingPathExtension().lastPathComponent
            let ext = isDirectory || url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let cleaned = sanitizeName(stem) + ext
            guard cleaned != originalName, !cleaned.isEmpty else { continue }
            let destination = url.deletingLastPathComponent().appendingPathComponent(cleaned)
            operations.append(BatchFileOperation(
                source: url,
                destination: destination,
                isDirectory: isDirectory,
                state: fileManager.fileExists(atPath: destination.path) ? .invalid("目标已存在") : .ready
            ))
        }
        return invalidatingDuplicateDestinations(operations)
            .sorted { pathDepth($0.source) > pathDepth($1.source) }
    }

    static func executeCopies(
        _ operations: [BatchFileOperation],
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) -> ([BatchFileOperation], FileOperationSummary) {
        execute(operations, progress: progress) { operation in
            try fileManager.createDirectory(at: operation.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: operation.source, to: operation.destination)
        }
    }

    static func executeMoves(
        _ operations: [BatchFileOperation],
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) -> ([BatchFileOperation], FileOperationSummary) {
        execute(operations, progress: progress) { operation in
            try fileManager.moveItem(at: operation.source, to: operation.destination)
        }
    }

    static func sanitizeName(_ name: String) -> String {
        var result = ""
        var previousUnderscore = false
        for scalar in name.unicodeScalars {
            let allowed = CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
            if allowed {
                result.unicodeScalars.append(scalar)
                previousUnderscore = scalar == "_"
            } else if !previousUnderscore {
                result.append("_")
                previousUnderscore = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func regularFiles(in root: URL, fileManager: FileManager) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where try url.resourceValues(forKeys: keys).isRegularFile == true {
            files.append(url)
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func execute(
        _ operations: [BatchFileOperation],
        progress: @escaping @Sendable (Int, Int, String) -> Void,
        action: (BatchFileOperation) throws -> Void
    ) -> ([BatchFileOperation], FileOperationSummary) {
        var results = operations
        var succeeded = 0
        for index in results.indices {
            defer { progress(index + 1, results.count, results[index].source.path) }
            guard results[index].state.isExecutable else { continue }
            do {
                try action(results[index])
                results[index].state = .success
                succeeded += 1
            } catch {
                results[index].state = .failed(error.localizedDescription)
            }
        }
        return (results, FileOperationSummary(total: results.count, succeeded: succeeded))
    }

    private static func pathDepth(_ url: URL) -> Int { url.pathComponents.count }

    private static func invalidatingDuplicateDestinations(
        _ operations: [BatchFileOperation]
    ) -> [BatchFileOperation] {
        let ready = operations.filter(\.state.isExecutable)
        let counts = Dictionary(grouping: ready, by: { $0.destination.standardizedFileURL.path }).mapValues(\.count)
        return operations.map { operation in
            guard operation.state.isExecutable,
                  counts[operation.destination.standardizedFileURL.path, default: 0] > 1 else { return operation }
            var duplicate = operation
            duplicate.state = .invalid("目标路径重复")
            return duplicate
        }
    }
}
