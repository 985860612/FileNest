import Foundation

enum FileManagementMode: String, CaseIterable, Identifiable {
    case export = "导出目录"
    case copy = "批量复制"
    case trash = "移到废纸篓"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .export: "tablecells"
        case .copy: "doc.on.doc"
        case .trash: "trash"
        }
    }
}

struct FileCatalogEntry: Identifiable, Equatable, Sendable {
    let fullPath: String
    let directory: String
    let fileName: String
    let fileExtension: String
    let sizeInBytes: UInt64

    var id: String { fullPath }

    var sizeInKilobytes: String {
        String(format: "%.2f", Double(sizeInBytes) / 1024)
    }

    var spreadsheetRow: [String] {
        [fullPath, directory, fileName, fileExtension, sizeInKilobytes]
    }
}

struct XLSXColumn: Identifiable, Hashable, Sendable {
    let index: Int
    let title: String

    var id: Int { index }
}

struct XLSXSheet: Equatable, Sendable {
    let columns: [XLSXColumn]
    let rows: [[String]]

    func value(row: [String], column: XLSXColumn) -> String {
        guard row.indices.contains(column.index) else { return "" }
        return row[column.index]
    }
}

enum FileOperationState: Equatable, Sendable {
    case ready
    case success
    case missing
    case invalid(String)
    case failed(String)

    var label: String {
        switch self {
        case .ready: "准备执行"
        case .success: "成功"
        case .missing: "文件不存在"
        case .invalid(let message), .failed(let message): message
        }
    }

    var isExecutable: Bool {
        if case .ready = self { return true }
        return false
    }
}

struct FileOperationPreview: Identifiable, Equatable, Sendable {
    let id: Int
    let sourcePath: String
    let destinationPath: String?
    var state: FileOperationState
}

struct FileOperationSummary: Equatable, Sendable {
    let total: Int
    let succeeded: Int

    var failed: Int { total - succeeded }
}

enum FileManagementError: LocalizedError, Equatable {
    case directoryRequired
    case workbookRequired
    case columnRequired
    case noRows
    case invalidWorkbook(String)

    var errorDescription: String? {
        switch self {
        case .directoryRequired: "请选择目录。"
        case .workbookRequired: "请选择 Excel 文件。"
        case .columnRequired: "请选择要使用的 Excel 列。"
        case .noRows: "Excel 工作表没有可执行的数据行。"
        case .invalidWorkbook(let message): "无法读取 Excel：\(message)"
        }
    }
}
