import Foundation
import PaddleOCRCoreML

public enum DocumentRecognitionError: LocalizedError {
    case modelsMissing
    case noDocuments
    case unsupportedInput(String)
    case resultMissing

    public var errorDescription: String? {
        switch self {
        case .modelsMissing: "识别模型尚未下载，或模型校验未通过。"
        case .noDocuments: "请先选择图片或 PDF。"
        case .unsupportedInput(let name): "不支持的文档格式：\(name)"
        case .resultMissing: "没有可导出的识别结果。"
        }
    }
}

public enum DocumentExportFormat: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON"
    case markdown = "Markdown"
    case html = "HTML"
    case docx = "DOCX"
    case xlsx = "XLSX"

    public var id: String { rawValue }
    public var fileExtension: String { rawValue.lowercased() == "markdown" ? "md" : rawValue.lowercased() }
}

public struct RecognitionModelComponent: Sendable {
    public let title: String
    public let artifact: PaddleOCRModelArtifact
}

public struct RecognitionModelProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
}

public struct DocumentRecognitionConfiguration: Sendable {
    public var maxConcurrentDocuments = 2
    public var classifyOrientation = true
    public var unwarpDocument = false
    public var recognizeTables = true
    public var recognizeFormulae = true
    public var recognizeCharts = false

    public init(
        maxConcurrentDocuments: Int = 2,
        classifyOrientation: Bool = true,
        unwarpDocument: Bool = false,
        recognizeTables: Bool = true,
        recognizeFormulae: Bool = true,
        recognizeCharts: Bool = false
    ) {
        self.maxConcurrentDocuments = maxConcurrentDocuments
        self.classifyOrientation = classifyOrientation
        self.unwarpDocument = unwarpDocument
        self.recognizeTables = recognizeTables
        self.recognizeFormulae = recognizeFormulae
        self.recognizeCharts = recognizeCharts
    }

    public var normalizedConcurrency: Int { min(max(maxConcurrentDocuments, 1), 4) }

    var structureOptions: PPStructureV3Options {
        var options = PPStructureV3Options()
        options.classifyDocumentOrientation = classifyOrientation
        options.unwarpDocument = unwarpDocument
        options.recognizeTables = recognizeTables
        options.recognizeFormulae = recognizeFormulae
        options.recognizeCharts = recognizeCharts
        return options
    }
}

public actor DocumentRecognitionService {
    public static let sdkVersion = PaddleOCRCoreML.version
    public static let supportedExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "webp"
    ]
    public static let modelComponents: [RecognitionModelComponent] = [
        .init(title: "PP-OCRv5 文本检测", artifact: PaddleOCRModelCatalog.ocrV5ServerDetection),
        .init(title: "PP-OCRv5 文本识别", artifact: PaddleOCRModelCatalog.ocrV5ServerRecognition),
        .init(title: "PP-DocLayout 版面分析", artifact: PaddleOCRModelCatalog.documentLayout),
        .init(title: "PP-DocBlockLayout 阅读顺序", artifact: PaddleOCRModelCatalog.documentBlockLayout),
        .init(title: "文档方向分类", artifact: PaddleOCRModelCatalog.documentOrientation),
        .init(title: "UVDoc 文档矫正", artifact: PaddleOCRModelCatalog.documentUnwarping),
        .init(title: "表格类型分类", artifact: PaddleOCRModelCatalog.tableClassification),
        .init(title: "SLANeXt 有线表格", artifact: PaddleOCRModelCatalog.wiredTableStructure),
        .init(title: "RT-DETR 有线单元格", artifact: PaddleOCRModelCatalog.wiredTableCells),
        .init(title: "SLANet 无线表格", artifact: PaddleOCRModelCatalog.wirelessTableStructure),
        .init(title: "RT-DETR 无线单元格", artifact: PaddleOCRModelCatalog.wirelessTableCells),
    ]

    public let modelRoot: URL
    private var engine: PPStructureV3Engine?
    private var validatedModelsReady: Bool?

    public init(modelRoot: URL = DocumentRecognitionService.defaultModelRoot()) {
        self.modelRoot = modelRoot
    }

    public static func defaultModelRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FileNest/PaddleOCRModels", isDirectory: true)
    }

    public static func accepts(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func modelsReady() -> Bool {
        if let validatedModelsReady { return validatedModelsReady }
        let ready = Self.modelComponents.allSatisfy { component in
            let directory = modelRoot.appendingPathComponent(component.artifact.name, isDirectory: true)
            let model = directory.appendingPathComponent("inference.onnx")
            let config = directory.appendingPathComponent("inference.yml")
            return (try? PaddleOCRModelStore.verify(file: model, sha256: component.artifact.modelSHA256)) == true
                && (try? PaddleOCRModelStore.verify(file: config, sha256: component.artifact.configurationSHA256)) == true
        }
        validatedModelsReady = ready
        return ready
    }

    public func downloadModels(
        progress: @Sendable (RecognitionModelProgress) -> Void = { _ in }
    ) async throws {
        engine = nil
        validatedModelsReady = nil
        for (index, component) in Self.modelComponents.enumerated() {
            progress(.init(completed: index, total: Self.modelComponents.count, name: component.title))
            _ = try await PaddleOCRModelStore.download(component.artifact, into: modelRoot)
        }
        validatedModelsReady = true
        progress(.init(completed: Self.modelComponents.count, total: Self.modelComponents.count, name: "模型校验完成"))
    }

    public func analyze(
        documents: [URL],
        configuration: DocumentRecognitionConfiguration
    ) throws -> StructureBatchResult {
        guard !documents.isEmpty else { throw DocumentRecognitionError.noDocuments }
        if let unsupported = documents.first(where: { !Self.accepts($0) }) {
            throw DocumentRecognitionError.unsupportedInput(unsupported.lastPathComponent)
        }
        guard modelsReady() else { throw DocumentRecognitionError.modelsMissing }
        let engine = try engine ?? makeEngine()
        self.engine = engine
        return try engine.analyzeBatch(
            documentsAt: documents,
            options: configuration.structureOptions,
            maxConcurrentDocuments: configuration.normalizedConcurrency
        )
    }

    private func makeEngine() throws -> PPStructureV3Engine {
        let downloaded: [String: (model: URL, configuration: URL)] = Dictionary(uniqueKeysWithValues: Self.modelComponents.map { component in
            let directory = modelRoot.appendingPathComponent(component.artifact.name, isDirectory: true)
            return (component.artifact.name, (
                model: directory.appendingPathComponent("inference.onnx"),
                configuration: directory.appendingPathComponent("inference.yml")
            ))
        })
        func artifact(_ catalog: PaddleOCRModelArtifact) -> (model: URL, configuration: URL) {
            downloaded[catalog.name]!
        }
        let detection = artifact(PaddleOCRModelCatalog.ocrV5ServerDetection)
        let recognition = artifact(PaddleOCRModelCatalog.ocrV5ServerRecognition)
        let layout = artifact(PaddleOCRModelCatalog.documentLayout)
        let wired = artifact(PaddleOCRModelCatalog.wiredTableStructure)
        let wireless = artifact(PaddleOCRModelCatalog.wirelessTableStructure)
        func optional(_ relativePath: String) -> URL? {
            let url = modelRoot.appendingPathComponent(relativePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let models = PPStructureV3Models(
            ocr: OCRModelConfiguration(
                detectionModel: detection.model,
                recognitionModel: recognition.model,
                recognitionConfiguration: recognition.configuration
            ),
            layoutModel: layout.model,
            wiredTableModel: wired.model,
            wiredTableConfiguration: wired.configuration,
            wirelessTableModel: wireless.model,
            wirelessTableConfiguration: wireless.configuration,
            tableClassificationModel: artifact(PaddleOCRModelCatalog.tableClassification).model,
            documentOrientationModel: artifact(PaddleOCRModelCatalog.documentOrientation).model,
            documentUnwarpingModel: artifact(PaddleOCRModelCatalog.documentUnwarping).model,
            regionLayoutModel: artifact(PaddleOCRModelCatalog.documentBlockLayout).model,
            wiredTableCellsModel: artifact(PaddleOCRModelCatalog.wiredTableCells).model,
            wirelessTableCellsModel: artifact(PaddleOCRModelCatalog.wirelessTableCells).model,
            tableOrientationModel: artifact(PaddleOCRModelCatalog.documentOrientation).model,
            formulaEncoderModel: optional("Formula/encoder.onnx"),
            formulaDecoderModel: optional("Formula/decoder.onnx"),
            formulaTokenizer: optional("Formula/tokenizer.json"),
            chartEncoderModel: optional("Chart/encoder.onnx"),
            chartDecoderModel: optional("Chart/decoder.onnx"),
            chartPromptIDs: optional("Chart/prompt_ids.txt"),
            chartTokenizer: optional("Chart/tokenizer.json")
        )
        // Server PP-Structure models currently match the official CPU path most reliably.
        return try PPStructureV3Engine(models: models, executionProvider: .cpu)
    }

    public nonisolated static func export(
        _ document: StructureDocumentResult,
        format: DocumentExportFormat,
        to destination: URL
    ) throws {
        switch format {
        case .json:
            try StructureExporter.json(document).write(to: destination, options: .atomic)
        case .markdown:
            try Data(document.markdown.utf8).write(to: destination, options: .atomic)
        case .html:
            try Data(StructureExporter.html(document).utf8).write(to: destination, options: .atomic)
        case .docx:
            try StructureExporter.writeDOCX(document, to: destination)
        case .xlsx:
            try StructureExporter.writeXLSX(document, to: destination)
        }
    }
}
