import Foundation

enum FileCatalogService {
    static let spreadsheetHeaders = ["完整路径", "所在目录", "文件名", "扩展名", "大小(KB)"]

    static func export(
        directory: URL,
        to destination: URL,
        engine: ArchiveEngine = .shared,
        progress: @escaping @Sendable (_ completed: Int, _ currentPath: String) -> Void = { _, _ in }
    ) throws -> [FileCatalogEntry] {
        let entries = try scan(directory: directory, recursively: true, progress: progress)
        try XLSXDocument.write(
            headers: spreadsheetHeaders,
            rows: entries.map(\.spreadsheetRow),
            to: destination,
            engine: engine
        )
        return entries
    }

    static func desktopExportURL(
        for directory: URL,
        desktop: URL,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "文件目录_\(directory.lastPathComponent)_\(formatter.string(from: date))"
        var destination = desktop.appendingPathComponent("\(baseName).xlsx")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = desktop.appendingPathComponent("\(baseName)_\(suffix).xlsx")
            suffix += 1
        }
        return destination
    }

    static func scan(
        directory: URL,
        recursively: Bool,
        progress: @escaping @Sendable (_ completed: Int, _ currentPath: String) -> Void = { _, _ in }
    ) throws -> [FileCatalogEntry] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let options: FileManager.DirectoryEnumerationOptions = recursively
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: options
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var entries: [FileCatalogEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            entries.append(FileCatalogEntry(
                fullPath: url.path,
                directory: url.deletingLastPathComponent().path,
                fileName: name,
                fileExtension: url.pathExtension,
                sizeInBytes: UInt64(values.fileSize ?? 0)
            ))
            progress(entries.count, url.path)
        }
        return entries.sorted { $0.fullPath.localizedStandardCompare($1.fullPath) == .orderedAscending }
    }
}
