import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FileManagementWorkspaceModel: ObservableObject {
    @Published var mode: FileManagementMode = .export {
        didSet {
            if mode != oldValue {
                operations = []
                if !isWorking { statusMessage = mode.idleMessage }
            }
        }
    }
    @Published var directoryURL: URL?
    @Published var recursively = true
    @Published var catalogEntries: [FileCatalogEntry] = []
    @Published var workbookURL: URL?
    @Published var sheet: XLSXSheet?
    @Published var sourceColumn: XLSXColumn? {
        didSet { if sourceColumn != oldValue { operations = [] } }
    }
    @Published var destinationColumn: XLSXColumn? {
        didSet { if destinationColumn != oldValue { operations = [] } }
    }
    @Published var pathColumn: XLSXColumn? {
        didSet { if pathColumn != oldValue { operations = [] } }
    }
    @Published var operations: [FileOperationPreview] = []
    @Published var isWorking = false
    @Published var progressFraction: Double?
    @Published var currentPath = ""
    @Published var statusMessage = "选择一种文件管理操作"
    @Published var errorMessage: String?
    @Published var showsTrashConfirmation = false

    private let engine: ArchiveEngine

    init(engine: ArchiveEngine = .shared) {
        self.engine = engine
    }

    var columns: [XLSXColumn] { sheet?.columns ?? [] }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directoryURL = url
        catalogEntries = []
        statusMessage = "已选择 \(url.lastPathComponent)"
    }

    func exportDirectory() {
        guard let directoryURL else {
            errorMessage = FileManagementError.directoryRequired.localizedDescription
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = "文件目录_\(directoryURL.lastPathComponent)_\(Self.timestamp()).xlsx"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        beginWork(message: "正在扫描目录…")
        let recursively = recursively
        let engine = engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let entries = try FileCatalogService.scan(
                    directory: directoryURL,
                    recursively: recursively,
                    progress: { completed, path in
                        DispatchQueue.main.async {
                            self?.currentPath = path
                            self?.statusMessage = "已扫描 \(completed) 个文件"
                        }
                    }
                )
                try XLSXDocument.write(
                    headers: FileCatalogService.spreadsheetHeaders,
                    rows: entries.map(\.spreadsheetRow),
                    to: destination,
                    engine: engine
                )
                DispatchQueue.main.async {
                    self?.catalogEntries = entries
                    self?.finish(message: "导出完成，共 \(entries.count) 个文件", reveal: destination)
                }
            } catch {
                DispatchQueue.main.async { self?.fail(error) }
            }
        }
    }

    func chooseWorkbook() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.prompt = "打开"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadWorkbook(url)
    }

    func loadWorkbook(_ url: URL) {
        beginWork(message: "正在读取 Excel…")
        workbookURL = url
        sheet = nil
        operations = []
        let engine = engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let loaded = try XLSXDocument.read(from: url, engine: engine)
                DispatchQueue.main.async {
                    self?.sheet = loaded
                    self?.sourceColumn = loaded.columns.first
                    self?.destinationColumn = loaded.columns.dropFirst().first ?? loaded.columns.first
                    self?.pathColumn = loaded.columns.first
                    self?.finish(message: "已读取 \(loaded.rows.count) 行数据")
                }
            } catch {
                DispatchQueue.main.async { self?.fail(error) }
            }
        }
    }

    func preview() {
        guard let sheet else {
            errorMessage = FileManagementError.workbookRequired.localizedDescription
            return
        }
        switch mode {
        case .copy:
            guard let sourceColumn, let destinationColumn else {
                errorMessage = FileManagementError.columnRequired.localizedDescription
                return
            }
            operations = FileOperationService.copyPreview(
                sheet: sheet,
                sourceColumn: sourceColumn,
                destinationColumn: destinationColumn
            )
        case .trash:
            guard let pathColumn else {
                errorMessage = FileManagementError.columnRequired.localizedDescription
                return
            }
            operations = FileOperationService.trashPreview(sheet: sheet, pathColumn: pathColumn)
        case .export:
            return
        }
        statusMessage = "预览完成，共 \(operations.count) 项"
    }

    func executeCopy() {
        guard !operations.isEmpty else { preview(); return }
        beginWork(message: "正在复制文件…")
        let operations = operations
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (results, summary) = FileOperationService.executeCopies(
                operations,
                progress: Self.progressHandler(for: self)
            )
            DispatchQueue.main.async {
                self?.operations = results
                self?.finish(message: "复制完成：成功 \(summary.succeeded)，未完成 \(summary.failed)")
            }
        }
    }

    func requestTrash() {
        guard !operations.isEmpty else { preview(); return }
        showsTrashConfirmation = true
    }

    func executeTrash() {
        showsTrashConfirmation = false
        beginWork(message: "正在移到废纸篓…")
        let operations = operations
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (results, summary) = FileOperationService.executeTrash(
                operations,
                progress: Self.progressHandler(for: self)
            )
            DispatchQueue.main.async {
                self?.operations = results
                self?.finish(message: "处理完成：成功 \(summary.succeeded)，未完成 \(summary.failed)")
            }
        }
    }

    private func beginWork(message: String) {
        isWorking = true
        errorMessage = nil
        progressFraction = nil
        currentPath = ""
        statusMessage = message
    }

    private func finish(message: String, reveal url: URL? = nil) {
        isWorking = false
        progressFraction = 1
        statusMessage = message
        currentPath = ""
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func fail(_ error: Error) {
        isWorking = false
        errorMessage = error.localizedDescription
        statusMessage = "操作失败"
    }

    private nonisolated static func progressHandler(
        for model: FileManagementWorkspaceModel?
    ) -> @Sendable (Int, Int, String) -> Void {
        { completed, total, path in
            DispatchQueue.main.async {
                model?.progressFraction = total == 0 ? nil : Double(completed) / Double(total)
                model?.currentPath = path
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

private extension FileManagementMode {
    var idleMessage: String {
        switch self {
        case .export: "选择要扫描的文件夹"
        case .copy: "选择包含源路径和目标路径的 Excel"
        case .trash: "选择包含文件路径的 Excel"
        }
    }
}
