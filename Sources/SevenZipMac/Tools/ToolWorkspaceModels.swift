import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum FileToolMode: String, CaseIterable, Identifiable {
    case extensionRepair = "扩展名修复"
    case regexCopy = "正则复制"
    case sanitizeNames = "名称清理"
    var id: String { rawValue }
}

@MainActor
final class FileToolsWorkspaceModel: ObservableObject {
    @Published var mode: FileToolMode = .extensionRepair { didSet { operations = [] } }
    @Published var rootURL: URL?
    @Published var outputURL: URL?
    @Published var regexPattern = "(.+)"
    @Published var replacement = "$1"
    @Published var operations: [BatchFileOperation] = []
    @Published var isWorking = false
    @Published var statusMessage = "选择文件夹后生成操作预览"
    @Published var currentPath = ""
    @Published var errorMessage: String?
    @Published var showsExecutionConfirmation = false

    func chooseRoot() { rootURL = chooseDirectory(prompt: "选择来源目录") }
    func chooseOutput() { outputURL = chooseDirectory(prompt: "选择输出目录") }

    func preview() {
        guard let rootURL else { errorMessage = "请选择来源目录。"; return }
        if mode == .regexCopy, outputURL == nil { errorMessage = "正则复制需要选择输出目录。"; return }
        begin("正在扫描文件…")
        let mode = mode
        let outputURL = outputURL
        let pattern = regexPattern
        let replacement = replacement
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let operations: [BatchFileOperation] = switch mode {
                case .extensionRepair: try FileToolService.extensionRepairPreview(in: rootURL)
                case .regexCopy: try FileToolService.regexCopyPreview(
                    in: rootURL,
                    outputRoot: outputURL!,
                    pattern: pattern,
                    replacement: replacement
                )
                case .sanitizeNames: try FileToolService.sanitizePreview(in: rootURL)
                }
                DispatchQueue.main.async {
                    self?.operations = operations
                    self?.finish("预览完成：共 \(operations.count) 项，可执行 \(operations.filter(\.state.isExecutable).count) 项")
                }
            } catch { DispatchQueue.main.async { self?.fail(error) } }
        }
    }

    func requestExecution() {
        guard operations.contains(where: \.state.isExecutable) else { return }
        showsExecutionConfirmation = true
    }

    func execute() {
        showsExecutionConfirmation = false
        begin(mode == .regexCopy ? "正在复制文件…" : "正在重命名…")
        let mode = mode
        let operations = operations
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let progress: @Sendable (Int, Int, String) -> Void = { completed, total, path in
                DispatchQueue.main.async { self?.currentPath = "\(completed)/\(total) · \(path)" }
            }
            let (results, summary) = mode == .regexCopy
                ? FileToolService.executeCopies(operations, progress: progress)
                : FileToolService.executeMoves(operations, progress: progress)
            DispatchQueue.main.async {
                self?.operations = results
                self?.finish("处理完成：成功 \(summary.succeeded)，未完成 \(summary.failed)")
            }
        }
    }

    private func begin(_ message: String) { isWorking = true; errorMessage = nil; statusMessage = message; currentPath = "" }
    private func finish(_ message: String) { isWorking = false; statusMessage = message; currentPath = "" }
    private func fail(_ error: Error) { isWorking = false; errorMessage = error.localizedDescription; statusMessage = "操作失败" }
}

@MainActor
final class ImageToolsWorkspaceModel: ObservableObject {
    @Published var rootURL: URL?
    @Published var outputURL: URL?
    @Published var recursively = true
    @Published var maximumWidth = ""
    @Published var maximumHeight = ""
    @Published var quality = 0.82
    @Published var format: ImageOutputFormat = .keep
    @Published var replaceOriginals = false
    @Published var results: [ImageProcessingResult] = []
    @Published var isWorking = false
    @Published var statusMessage = "选择图片目录并配置输出参数"
    @Published var errorMessage: String?
    @Published var showsReplaceConfirmation = false

    func chooseRoot() { rootURL = chooseDirectory(prompt: "选择图片目录") }
    func chooseOutput() { outputURL = chooseDirectory(prompt: "选择输出目录") }
    func requestRun() { replaceOriginals ? (showsReplaceConfirmation = true) : run() }

    func run() {
        showsReplaceConfirmation = false
        guard let rootURL else { errorMessage = "请选择图片目录。"; return }
        let options = ImageProcessingOptions(
            maximumWidth: Int(maximumWidth) ?? 0,
            maximumHeight: Int(maximumHeight) ?? 0,
            quality: quality,
            format: format,
            replaceOriginals: replaceOriginals
        )
        isWorking = true
        errorMessage = nil
        statusMessage = "正在处理图片…"
        let outputURL = outputURL
        let recursively = recursively
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let results = try ImageProcessingService.processDirectory(
                    rootURL,
                    outputRoot: outputURL,
                    recursively: recursively,
                    options: options
                )
                DispatchQueue.main.async {
                    self?.results = results
                    self?.isWorking = false
                    self?.statusMessage = "处理完成：成功 \(results.filter { $0.error == nil }.count)，失败 \(results.filter { $0.error != nil }.count)"
                }
            } catch { DispatchQueue.main.async { self?.isWorking = false; self?.errorMessage = error.localizedDescription } }
        }
    }
}

enum PDFToolMode: String, CaseIterable, Identifiable {
    case imagesToPDF = "图片转 PDF"
    case merge = "排序合并"
    case split = "关键字拆分"
    case regex = "正则提取"
    var id: String { rawValue }
}

@MainActor
final class PDFToolsWorkspaceModel: ObservableObject {
    @Published var mode: PDFToolMode = .imagesToPDF {
        didSet { results = []; mergePreview = []; extractedRows = [] }
    }
    @Published var rootURL: URL?
    @Published var outputURL: URL?
    @Published var recursively = true
    @Published var sortConfiguration = ""
    @Published var keyword = ""
    @Published var regexPattern = ""
    @Published var results: [PDFBatchResult] = []
    @Published var mergePreview: [PDFMergePreviewEntry] = []
    @Published var extractedRows: [PDFExtractionRow] = []
    @Published var isWorking = false
    @Published var statusMessage = "选择目录和处理方式"
    @Published var errorMessage: String?

    private let engine: ArchiveEngine
    init(engine: ArchiveEngine = .shared) { self.engine = engine }

    func chooseRoot() { rootURL = chooseDirectory(prompt: "选择来源目录") }
    func chooseOutput() { outputURL = chooseDirectory(prompt: "选择输出目录") }

    func previewMerge() {
        guard let rootURL else { errorMessage = "请选择来源目录。"; return }
        do {
            mergePreview = try PDFToolService.batchMergePreview(root: rootURL, sortConfiguration: sortConfiguration)
            statusMessage = "排序预览完成：\(mergePreview.count) 个文件"
        } catch { errorMessage = error.localizedDescription }
    }

    func run() {
        guard let rootURL else { errorMessage = "请选择来源目录。"; return }
        if mode == .regex { runRegexExport(rootURL: rootURL); return }
        if mode == .split, keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请输入拆分关键字。"; return
        }
        isWorking = true
        errorMessage = nil
        statusMessage = "正在处理 PDF…"
        let mode = mode
        let outputURL = outputURL
        let recursively = recursively
        let sortConfiguration = sortConfiguration
        let keyword = keyword
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let results: [PDFBatchResult]
                switch mode {
                case .imagesToPDF:
                    results = try PDFToolService.convertImagesToPDF(in: rootURL, outputRoot: outputURL, recursively: recursively)
                case .merge:
                    results = try PDFToolService.batchMergeChildDirectories(
                        root: rootURL,
                        outputRoot: outputURL,
                        sortConfiguration: sortConfiguration
                    )
                case .split:
                    let files = try PDFToolService.pdfFiles(in: rootURL, recursively: recursively)
                    results = files.map { file in
                        do {
                            let outputs = try PDFToolService.splitPDF(file, keyword: keyword, outputRoot: outputURL ?? rootURL)
                            return PDFBatchResult(source: file, destination: outputs.first, error: nil)
                        } catch {
                            return PDFBatchResult(source: file, destination: nil, error: error.localizedDescription)
                        }
                    }
                case .regex: results = []
                }
                DispatchQueue.main.async {
                    self?.results = results
                    self?.isWorking = false
                    self?.statusMessage = "处理完成：成功 \(results.filter { $0.error == nil }.count)，失败 \(results.filter { $0.error != nil }.count)"
                }
            } catch { DispatchQueue.main.async { self?.isWorking = false; self?.errorMessage = error.localizedDescription } }
        }
    }

    private func runRegexExport(rootURL: URL) {
        guard !regexPattern.isEmpty else { errorMessage = "请输入正则表达式。"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = "PDF正则提取_\(Self.timestamp()).xlsx"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isWorking = true
        errorMessage = nil
        statusMessage = "正在提取 PDF 文本…"
        let recursively = recursively
        let pattern = regexPattern
        let engine = engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let files = try PDFToolService.pdfFiles(in: rootURL, recursively: recursively)
                let rows = try PDFToolService.extractRegex(from: files, pattern: pattern)
                try XLSXDocument.write(
                    headers: ["文件路径", "文件名", "提取内容"],
                    rows: rows.map(\.spreadsheetRow),
                    to: destination,
                    engine: engine
                )
                DispatchQueue.main.async {
                    self?.extractedRows = rows
                    self?.isWorking = false
                    self?.statusMessage = "提取完成：\(rows.count) 条"
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch { DispatchQueue.main.async { self?.isWorking = false; self?.errorMessage = error.localizedDescription } }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd_HHmmss"; return formatter.string(from: Date())
    }
}

@MainActor
final class SpreadsheetToolsWorkspaceModel: ObservableObject {
    @Published var workbookURL: URL?
    @Published var sheet: XLSXSheet?
    @Published var groupingColumn: XLSXColumn?
    @Published var groupedRows: [[String]] = []
    @Published var isWorking = false
    @Published var statusMessage = "选择 Excel 和分组列"
    @Published var errorMessage: String?

    private let engine: ArchiveEngine
    init(engine: ArchiveEngine = .shared) { self.engine = engine }

    func chooseWorkbook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workbookURL = url
        isWorking = true
        let engine = engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let sheet = try XLSXDocument.read(from: url, engine: engine)
                DispatchQueue.main.async {
                    self?.sheet = sheet
                    self?.groupingColumn = sheet.columns.first
                    self?.isWorking = false
                    self?.statusMessage = "已读取 \(sheet.rows.count) 行"
                }
            } catch { DispatchQueue.main.async { self?.isWorking = false; self?.errorMessage = error.localizedDescription } }
        }
    }

    func exportGrouped() {
        guard let sheet, let groupingColumn else { errorMessage = "请选择 Excel 和分组列。"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = "分组合并_\(workbookURL?.deletingPathExtension().lastPathComponent ?? "结果").xlsx"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isWorking = true
        let engine = engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let rows = try SpreadsheetToolService.groupedRows(sheet: sheet, groupingColumn: groupingColumn)
                try XLSXDocument.write(headers: sheet.columns.map(\.title), rows: rows, to: destination, engine: engine)
                DispatchQueue.main.async {
                    self?.groupedRows = rows
                    self?.isWorking = false
                    self?.statusMessage = "分组合并完成：\(rows.count) 行"
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch { DispatchQueue.main.async { self?.isWorking = false; self?.errorMessage = error.localizedDescription } }
        }
    }
}

@MainActor
private func chooseDirectory(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
}
