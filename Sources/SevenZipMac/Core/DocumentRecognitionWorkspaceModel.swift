import AppKit
import Combine
import FileNestOCRCore
import Foundation
import PaddleOCRCoreML
import UniformTypeIdentifiers

enum RecognitionItemState: Equatable {
    case pending
    case processing
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .pending: "等待处理"
        case .processing: "识别中"
        case .completed: "完成"
        case .failed(let message): message
        }
    }
}

struct RecognitionWorkspaceItem: Identifiable {
    let id: URL
    let source: URL
    var state: RecognitionItemState = .pending
    var result: StructureDocumentResult?
    var seconds: Double?

    var pageCount: Int { result?.pages.count ?? 0 }
    var blockCount: Int { result?.pages.reduce(0) { $0 + $1.blocks.count } ?? 0 }
    var lineCount: Int { result?.pages.reduce(0) { $0 + $1.overallOCR.lines.count } ?? 0 }
}

@MainActor
final class DocumentRecognitionWorkspaceModel: ObservableObject {
    @Published var items: [RecognitionWorkspaceItem] = []
    @Published var isWorking = false
    @Published var isDownloading = false
    @Published var modelsReady = false
    @Published var statusMessage = "选择图片或 PDF，首次使用请下载识别模型"
    @Published var modelProgress = ""
    @Published var errorMessage: String?
    @Published var maxConcurrentDocuments = 2
    @Published var classifyOrientation = true
    @Published var unwarpDocument = false
    @Published var recognizeTables = true
    @Published var exportFormat: DocumentExportFormat = .markdown
    @Published var metrics: StructureBatchMetrics?

    let mode: DocumentRecognitionMode
    let service: DocumentRecognitionService

    init(
        mode: DocumentRecognitionMode = .structure,
        service: DocumentRecognitionService = DocumentRecognitionService()
    ) {
        self.mode = mode
        self.service = service
        if mode == .ocr {
            maxConcurrentDocuments = 1
            classifyOrientation = false
            recognizeTables = false
            statusMessage = "选择图片或 PDF，首次使用只需下载 2 个 OCR 模型"
        }
        refreshModelStatus()
    }

    func refreshModelStatus() {
        Task {
            modelsReady = await service.modelsReady(mode: mode)
            if modelsReady, items.isEmpty { statusMessage = "模型已就绪，请选择图片或 PDF" }
        }
    }

    func chooseDocuments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf, .image]
        panel.prompt = "添加"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func add(_ urls: [URL]) {
        let discovered = urls.flatMap(Self.discover)
        let existing = Set(items.map(\.source.standardizedFileURL))
        let additions = discovered
            .filter { !existing.contains($0.standardizedFileURL) }
            .map { RecognitionWorkspaceItem(id: $0.standardizedFileURL, source: $0.standardizedFileURL) }
        items.append(contentsOf: additions)
        items.sort { $0.source.path.localizedStandardCompare($1.source.path) == .orderedAscending }
        metrics = nil
        statusMessage = items.isEmpty ? "没有找到支持的图片或 PDF" : "已选择 \(items.count) 个文档"
    }

    func clear() {
        guard !isWorking else { return }
        items = []
        metrics = nil
        statusMessage = modelsReady ? "模型已就绪，请选择图片或 PDF" : "首次使用请下载识别模型"
    }

    func downloadModels() {
        guard !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        statusMessage = mode == .ocr ? "正在下载并校验 PP-OCRv5 模型…" : "正在下载并校验 PP-StructureV3 模型…"
        Task {
            do {
                try await service.downloadModels(mode: mode) { progress in
                    Task { @MainActor in
                        self.modelProgress = "\(progress.completed)/\(progress.total) · \(progress.name)"
                    }
                }
                modelsReady = true
                isDownloading = false
                modelProgress = ""
                statusMessage = "模型下载和 SHA-256 校验完成"
            } catch {
                isDownloading = false
                errorMessage = error.localizedDescription
                statusMessage = "模型下载失败"
            }
        }
    }

    func recognize() {
        guard !items.isEmpty else { errorMessage = DocumentRecognitionError.noDocuments.localizedDescription; return }
        guard modelsReady else { errorMessage = DocumentRecognitionError.modelsMissing.localizedDescription; return }
        isWorking = true
        errorMessage = nil
        metrics = nil
        for index in items.indices { items[index].state = .processing; items[index].result = nil; items[index].seconds = nil }
        statusMessage = mode == .ocr
            ? "正在进行纯文字 OCR：\(items.count) 个文档…"
            : "正在批量识别 \(items.count) 个文档…"
        let documents = items.map(\.source)
        let configuration = DocumentRecognitionConfiguration(
            mode: mode,
            maxConcurrentDocuments: maxConcurrentDocuments,
            classifyOrientation: classifyOrientation,
            unwarpDocument: unwarpDocument,
            recognizeTables: recognizeTables
        )
        Task {
            do {
                let batch = try await service.analyze(documents: documents, configuration: configuration)
                for index in items.indices {
                    items[index].result = batch.documents[index]
                    items[index].seconds = batch.metrics.itemSeconds[index]
                    items[index].state = .completed
                }
                metrics = batch.metrics
                isWorking = false
                statusMessage = String(
                    format: "完成 %d 个文档 · %.2f 秒 · %.3f 文档/秒 · P50 %.2f 秒 · P95 %.2f 秒",
                    batch.metrics.documentCount,
                    batch.metrics.totalSeconds,
                    batch.metrics.throughputPerSecond,
                    batch.metrics.p50Seconds,
                    batch.metrics.p95Seconds
                )
            } catch {
                for index in items.indices { items[index].state = .failed(error.localizedDescription) }
                isWorking = false
                errorMessage = error.localizedDescription
                statusMessage = "识别失败"
            }
        }
    }

    func export(_ item: RecognitionWorkspaceItem) {
        guard let result = item.result else { errorMessage = DocumentRecognitionError.resultMissing.localizedDescription; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: exportFormat.fileExtension)!]
        panel.nameFieldStringValue = item.source.deletingPathExtension().lastPathComponent + "." + exportFormat.fileExtension
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try DocumentRecognitionService.export(result, format: exportFormat, to: destination)
            statusMessage = "已导出：\(destination.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { errorMessage = error.localizedDescription }
    }

    func exportAll() {
        let completed = items.compactMap { item -> (URL, StructureDocumentResult)? in
            item.result.map { (item.source, $0) }
        }
        guard !completed.isEmpty else { errorMessage = DocumentRecognitionError.resultMissing.localizedDescription; return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出到此处"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            for (source, result) in completed {
                let destination = Self.uniqueDestination(
                    in: directory,
                    stem: source.deletingPathExtension().lastPathComponent,
                    extension: exportFormat.fileExtension
                )
                try DocumentRecognitionService.export(result, format: exportFormat, to: destination)
            }
            statusMessage = "已导出 \(completed.count) 个 \(exportFormat.rawValue) 文件"
            NSWorkspace.shared.open(directory)
        } catch { errorMessage = error.localizedDescription }
    }

    private static func discover(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return DocumentRecognitionService.accepts(url) ? [url] : [] }
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var results: [URL] = []
        while let candidate = enumerator?.nextObject() as? URL {
            if (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
               DocumentRecognitionService.accepts(candidate) {
                results.append(candidate)
            }
        }
        return results
    }

    private static func uniqueDestination(in directory: URL, stem: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)_\(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
