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

enum CompressionDictionarySize: UInt64, CaseIterable, Identifiable {
    case automatic = 0
    case mib4 = 4_194_304
    case mib8 = 8_388_608
    case mib16 = 16_777_216
    case mib32 = 33_554_432
    case mib64 = 67_108_864
    case mib128 = 134_217_728
    case mib256 = 268_435_456
    case mib512 = 536_870_912

    var id: UInt64 { rawValue }
    var displayName: String {
        self == .automatic ? "自动" : "\(rawValue / 1_048_576) MB"
    }
}

enum ArchiveVolumePreset: String, CaseIterable, Identifiable {
    case none
    case mb10
    case mb50
    case mb100
    case mb500
    case gb1
    case gb2
    case gb4
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "不分卷"
        case .mb10: "10 MB"
        case .mb50: "50 MB"
        case .mb100: "100 MB"
        case .mb500: "500 MB"
        case .gb1: "1 GB"
        case .gb2: "2 GB"
        case .gb4: "4 GB"
        case .custom: "自定义"
        }
    }

    func bytes(customMegabytes: Int) -> UInt64 {
        switch self {
        case .none: 0
        case .mb10: 10 * 1_048_576
        case .mb50: 50 * 1_048_576
        case .mb100: 100 * 1_048_576
        case .mb500: 500 * 1_048_576
        case .gb1: 1_024 * 1_048_576
        case .gb2: 2_048 * 1_048_576
        case .gb4: 4_096 * 1_048_576
        case .custom: UInt64(max(0, min(customMegabytes, 1_048_576))) * 1_048_576
        }
    }
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
