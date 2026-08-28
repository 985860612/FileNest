import Foundation

enum ArchiveUtilities {
    static let readableExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz",
        "cab", "iso", "wim", "dmg", "apfs", "zst"
    ]

    static func looksLikeArchive(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased()) || ArchiveVolumeUtilities.isFirstVolume(url)
    }

    static func extractionFolder(for archive: URL) -> URL {
        let source = ArchiveVolumeUtilities.isFirstVolume(archive) ? archive.deletingPathExtension() : archive
        let parent = source.deletingLastPathComponent()
        var stem = source.deletingPathExtension().lastPathComponent
        if ["gz", "bz2", "xz"].contains(source.pathExtension.lowercased()),
           stem.lowercased().hasSuffix(".tar") {
            stem = String(stem.dropLast(4))
        }
        return uniqueURL(parent.appendingPathComponent(stem, isDirectory: true))
    }

    static func archiveDestination(
        for inputs: [URL],
        format: ArchiveFormat,
        volumeSize: UInt64 = 0
    ) -> URL {
        let first = inputs[0]
        let parent = first.deletingLastPathComponent()
        let stem = inputs.count == 1 ? first.lastPathComponent : "归档"
        let proposed = parent.appendingPathComponent(stem).appendingPathExtension(format.fileExtension)
        guard volumeSize > 0 else { return uniqueURL(proposed) }
        return uniqueVolumeArchiveURL(proposed)
    }

    private static func uniqueVolumeArchiveURL(
        _ proposed: URL,
        fileManager: FileManager = .default
    ) -> URL {
        func isAvailable(_ url: URL) -> Bool {
            !fileManager.fileExists(atPath: url.path)
                && !fileManager.fileExists(atPath: ArchiveVolumeUtilities.firstVolumeURL(for: url).path)
        }
        if isAvailable(proposed) { return proposed }
        let parent = proposed.deletingLastPathComponent()
        let pathExtension = proposed.pathExtension
        let base = proposed.deletingPathExtension().lastPathComponent
        for index in 2...10_000 {
            let candidate = parent
                .appendingPathComponent("\(base) \(index)")
                .appendingPathExtension(pathExtension)
            if isAvailable(candidate) { return candidate }
        }
        return parent
            .appendingPathComponent("\(base)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    static func uniqueURL(_ proposed: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }
        let isDirectory = proposed.hasDirectoryPath
        let parent = proposed.deletingLastPathComponent()
        let pathExtension = isDirectory ? "" : proposed.pathExtension
        let base = isDirectory
            ? proposed.lastPathComponent
            : proposed.deletingPathExtension().lastPathComponent
        for index in 2...10_000 {
            var candidate = parent.appendingPathComponent("\(base) \(index)", isDirectory: isDirectory)
            if !pathExtension.isEmpty { candidate.appendPathExtension(pathExtension) }
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return parent.appendingPathComponent("\(base)-\(UUID().uuidString)", isDirectory: isDirectory)
    }
}
