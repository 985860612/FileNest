import Foundation

struct PreparedArchive {
    let url: URL
    private let temporaryRoot: URL?

    init(url: URL, temporaryRoot: URL? = nil) {
        self.url = url
        self.temporaryRoot = temporaryRoot
    }

    func cleanUp() {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
    }
}

enum ArchiveVolumeUtilities {
    static func isFirstVolume(_ url: URL) -> Bool {
        guard url.pathExtension == "001" else { return false }
        return ArchiveUtilities.readableExtensions.contains(
            url.deletingPathExtension().pathExtension.lowercased()
        )
    }

    static func firstVolumeURL(for archive: URL) -> URL {
        URL(fileURLWithPath: archive.path + ".001")
    }

    static func split(
        archive: URL,
        volumeSize: UInt64,
        cancellation: ArchiveCancellation,
        progress: @escaping @Sendable (ArchiveProgress) -> Void,
        fileManager: FileManager = .default
    ) throws {
        guard volumeSize > 0 else { return }
        let attributes = try fileManager.attributesOfItem(atPath: archive.path)
        let totalSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let volumeCount = max(1, Int(totalSize / volumeSize + (totalSize % volumeSize == 0 ? 0 : 1)))
        let finalURLs = (1...volumeCount).map { volumeURL(for: archive, number: $0) }
        if let existing = finalURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            throw ArchiveEngineError.operationFailed("分卷文件已存在：\(existing.lastPathComponent)")
        }
        let temporaryURLs = finalURLs.map {
            URL(fileURLWithPath: $0.path + ".partial")
        }
        temporaryURLs.forEach { try? fileManager.removeItem(at: $0) }

        let input = try FileHandle(forReadingFrom: archive)
        var completed: UInt64 = 0
        var renamed: [URL] = []
        do {
            defer { try? input.close() }
            for (index, temporaryURL) in temporaryURLs.enumerated() {
                guard !cancellation.isCancelled else {
                    throw ArchiveEngineError.operationFailed("Cancelled")
                }
                guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
                    throw ArchiveEngineError.operationFailed("无法创建分卷：\(temporaryURL.lastPathComponent)")
                }
                let output = try FileHandle(forWritingTo: temporaryURL)
                defer { try? output.close() }
                var written: UInt64 = 0
                while written < volumeSize, completed < totalSize {
                    guard !cancellation.isCancelled else {
                        throw ArchiveEngineError.operationFailed("Cancelled")
                    }
                    let request = Int(min(4 * 1024 * 1024, volumeSize - written, totalSize - completed))
                    guard let data = try input.read(upToCount: request), !data.isEmpty else {
                        throw ArchiveEngineError.operationFailed("读取待分卷归档时提前结束")
                    }
                    try output.write(contentsOf: data)
                    let count = UInt64(data.count)
                    written += count
                    completed += count
                    progress(ArchiveProgress(
                        completed: completed,
                        total: totalSize,
                        currentPath: finalURLs[index].lastPathComponent
                    ))
                }
            }
            for index in temporaryURLs.indices {
                try fileManager.moveItem(at: temporaryURLs[index], to: finalURLs[index])
                renamed.append(finalURLs[index])
            }
            try fileManager.removeItem(at: archive)
        } catch {
            temporaryURLs.forEach { try? fileManager.removeItem(at: $0) }
            renamed.forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
    }

    static func prepareForReading(
        _ selectedURL: URL,
        cancellation: ArchiveCancellation,
        progress: @escaping @Sendable (ArchiveProgress) -> Void,
        fileManager: FileManager = .default
    ) throws -> PreparedArchive {
        guard isFirstVolume(selectedURL) else { return PreparedArchive(url: selectedURL) }
        let volumes = try volumeURLs(startingAt: selectedURL, fileManager: fileManager)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SevenZipMac-Volumes-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let joined = temporaryRoot.appendingPathComponent(
            selectedURL.deletingPathExtension().lastPathComponent
        )
        guard fileManager.createFile(atPath: joined.path, contents: nil) else {
            try? fileManager.removeItem(at: temporaryRoot)
            throw ArchiveEngineError.operationFailed("无法创建分卷读取缓存")
        }
        let total = try volumes.reduce(UInt64(0)) { partial, url in
            let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            return partial + (size?.uint64Value ?? 0)
        }
        var completed: UInt64 = 0
        do {
            let output = try FileHandle(forWritingTo: joined)
            defer { try? output.close() }
            for volume in volumes {
                let input = try FileHandle(forReadingFrom: volume)
                defer { try? input.close() }
                while true {
                    guard !cancellation.isCancelled else {
                        throw ArchiveEngineError.operationFailed("Cancelled")
                    }
                    guard let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { break }
                    try output.write(contentsOf: data)
                    completed += UInt64(data.count)
                    progress(ArchiveProgress(
                        completed: completed,
                        total: total,
                        currentPath: volume.lastPathComponent
                    ))
                }
            }
            return PreparedArchive(url: joined, temporaryRoot: temporaryRoot)
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            throw error
        }
    }

    static func volumeURLs(
        startingAt firstVolume: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard isFirstVolume(firstVolume) else { return [firstVolume] }
        let directory = firstVolume.deletingLastPathComponent()
        let prefix = firstVolume.deletingPathExtension().lastPathComponent + "."
        let numbered = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).compactMap { url -> (Int, URL)? in
            guard url.lastPathComponent.hasPrefix(prefix) else { return nil }
            let suffix = String(url.lastPathComponent.dropFirst(prefix.count))
            guard suffix.count >= 3,
                  suffix.allSatisfy(\.isNumber),
                  let number = Int(suffix), number > 0 else { return nil }
            return (number, url)
        }.sorted { $0.0 < $1.0 }
        guard numbered.first?.0 == 1 else {
            throw ArchiveEngineError.operationFailed("找不到第一个分卷")
        }
        for (offset, item) in numbered.enumerated() where item.0 != offset + 1 {
            throw ArchiveEngineError.operationFailed(
                "缺少分卷：\(volumeURL(for: firstVolume.deletingPathExtension(), number: offset + 1).lastPathComponent)"
            )
        }
        return numbered.map(\.1)
    }

    private static func volumeURL(for archive: URL, number: Int) -> URL {
        URL(fileURLWithPath: archive.path + "." + String(format: "%03d", number))
    }
}
