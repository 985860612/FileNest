import Foundation

enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case sevenZip = "7z"
    case zip
    case tar

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case extract = "解压"
    case compress = "压缩"

    var id: String { rawValue }
}

struct ArchiveEntry: Codable, Identifiable, Sendable {
    let path: String
    let size: UInt64
    let directory: Bool

    var id: String { path }
}

struct ArchiveProgress: Sendable {
    let completed: UInt64
    let total: UInt64
    let currentPath: String?

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

enum ArchiveEngineError: LocalizedError {
    case unavailable(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .operationFailed(let message): message
        }
    }
}

final class ArchiveCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock { cancelled = true }
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}

