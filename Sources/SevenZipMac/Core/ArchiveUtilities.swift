import Foundation

enum ArchiveUtilities {
    static let readableExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz",
        "cab", "iso", "wim", "dmg", "apfs", "zst"
    ]

    static func looksLikeArchive(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased())
    }

    static func extractionFolder(for archive: URL) -> URL {
        let parent = archive.deletingLastPathComponent()
        var stem = archive.deletingPathExtension().lastPathComponent
        if ["gz", "bz2", "xz"].contains(archive.pathExtension.lowercased()),
           stem.lowercased().hasSuffix(".tar") {
            stem = String(stem.dropLast(4))
        }
        return uniqueURL(parent.appendingPathComponent(stem, isDirectory: true))
    }

    static func archiveDestination(for inputs: [URL], format: ArchiveFormat) -> URL {
        let first = inputs[0]
        let parent = first.deletingLastPathComponent()
        let stem = inputs.count == 1 ? first.lastPathComponent : "归档"
        return uniqueURL(parent.appendingPathComponent(stem).appendingPathExtension(format.fileExtension))
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

