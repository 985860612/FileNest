import Foundation

enum FileCatalogService {
    static let spreadsheetHeaders = [
        "完整路径", "所在目录", "上级目录", "名称", "类型", "扩展名", "检测扩展名",
        "大小(字节)", "格式化大小", "创建时间", "修改时间"
    ]

    static func export(
        directory: URL,
        to destination: URL,
        engine: ArchiveEngine = .shared,
        progress: @escaping @Sendable (_ completed: Int, _ currentPath: String) -> Void = { _, _ in }
    ) throws -> [FileCatalogEntry] {
        let entries = try scan(directory: directory, recursively: true, includeDirectories: false, progress: progress)
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
        includeDirectories: Bool = false,
        progress: @escaping @Sendable (_ completed: Int, _ currentPath: String) -> Void = { _, _ in }
    ) throws -> [FileCatalogEntry] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]
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
            let isDirectory = values.isDirectory == true
            guard values.isRegularFile == true || (includeDirectories && isDirectory) else { continue }
            let name = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            entries.append(FileCatalogEntry(
                fullPath: url.path,
                directory: url.deletingLastPathComponent().path,
                parentDirectoryName: url.deletingLastPathComponent().lastPathComponent,
                fileName: name,
                fileExtension: isDirectory ? "" : url.pathExtension.lowercased(),
                detectedExtension: isDirectory ? "" : (DetectedFileType.detect(at: url)?.rawValue ?? ""),
                sizeInBytes: isDirectory ? 0 : UInt64(values.fileSize ?? 0),
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate,
                isDirectory: isDirectory
            ))
            progress(entries.count, url.path)
        }
        return entries.sorted { $0.fullPath.localizedStandardCompare($1.fullPath) == .orderedAscending }
    }
}
