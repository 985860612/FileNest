import CoreGraphics
import Foundation
import ImageIO
import PaddleOCRCoreML
import UniformTypeIdentifiers

public enum DocumentRecognitionMode: String, Sendable {
    case structure
    case ocr
}

public enum DocumentRecognitionProvider: String, CaseIterable, Identifiable, Sendable {
    case coreML = "coreml"
    case cpu

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .coreML: "CoreML 快速"
        case .cpu: "CPU 精确"
        }
    }

    fileprivate var sdkProvider: PaddleOCRExecutionProvider {
        switch self {
        case .coreML: .coreML
        case .cpu: .cpu
        }
    }
}

public enum DocumentRecognitionModelSize: String, CaseIterable, Identifiable, Sendable {
    case mobile
    case server

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mobile: "小模型（Mobile）"
        case .server: "大模型（Server）"
        }
    }
}

public enum DocumentRecognitionError: LocalizedError {
    case modelsMissing
    case noDocuments
    case unsupportedInput(String)
    case resultMissing
    case unsupportedOCRCombination

    public var errorDescription: String? {
        switch self {
        case .modelsMissing: "识别模型尚未下载，或模型校验未通过。"
        case .noDocuments: "请先选择图片或 PDF。"
        case .unsupportedInput(let name): "不支持的文档格式：\(name)"
        case .resultMissing: "没有可导出的识别结果。"
        case .unsupportedOCRCombination: "PP-OCRv5 Mobile 与 CoreML 的结果校验未通过；小模型请使用 CPU 精确模式。"
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
    public var mode: DocumentRecognitionMode = .structure
    public var ocrProvider: DocumentRecognitionProvider = .coreML
    public var ocrModelSize: DocumentRecognitionModelSize = .server
    public var maxConcurrentDocuments = 2
    public var classifyOrientation = true
    public var unwarpDocument = false
    public var recognizeTables = true
    public var recognizeFormulae = true
    public var recognizeCharts = false

    public init(
        mode: DocumentRecognitionMode = .structure,
        ocrProvider: DocumentRecognitionProvider = .coreML,
        ocrModelSize: DocumentRecognitionModelSize = .server,
        maxConcurrentDocuments: Int = 2,
        classifyOrientation: Bool = true,
        unwarpDocument: Bool = false,
        recognizeTables: Bool = true,
        recognizeFormulae: Bool = true,
        recognizeCharts: Bool = false
    ) {
        self.mode = mode
        self.ocrProvider = ocrProvider
        self.ocrModelSize = ocrModelSize
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
    private static let mobileDetectionArtifact = modelArtifact(
        name: "PP-OCRv5_mobile_det_onnx",
        revision: "e6f4fa85f00e168c862bc462aebca69eef9b3d3d",
        modelSHA256: "a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d",
        configurationSHA256: "98069072e1b6b37d727fd9d9f11725faa46d6ea0de012f2ed26caea011c37699"
    )
    private static let mobileRecognitionArtifact = modelArtifact(
        name: "PP-OCRv5_mobile_rec_onnx",
        revision: "ed152b8b495f84de93cda5709d768548a9127622",
        modelSHA256: "da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092",
        configurationSHA256: "5dfeb2777f6d0db8177d8128a8acfcf6e6276dc4ac73ea3bf0dc06d6a5e85d8e"
    )

    private struct OCRSessionKey: Hashable {
        let provider: DocumentRecognitionProvider
        let modelSize: DocumentRecognitionModelSize
    }

    private struct ModelSelectionKey: Hashable {
        let mode: DocumentRecognitionMode
        let modelSize: DocumentRecognitionModelSize
    }

    public let modelRoot: URL
    private var engine: PPStructureV3Engine?
    private var ocrEngines: [OCRSessionKey: OCRRecognizer] = [:]
    private var validatedSelections: Set<ModelSelectionKey> = []

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
        modelsReady(mode: .structure)
    }

    public func modelsReady(mode: DocumentRecognitionMode) -> Bool {
        modelsReady(mode: mode, modelSize: .server)
    }

    public func modelsReady(
        mode: DocumentRecognitionMode,
        modelSize: DocumentRecognitionModelSize
    ) -> Bool {
        let selection = ModelSelectionKey(mode: mode, modelSize: mode == .ocr ? modelSize : .server)
        if validatedSelections.contains(selection) { return true }
        let ready = Self.modelComponents(for: mode, modelSize: modelSize).allSatisfy { component in
            let directory = modelRoot.appendingPathComponent(component.artifact.name, isDirectory: true)
            let model = directory.appendingPathComponent("inference.onnx")
            let config = directory.appendingPathComponent("inference.yml")
            return (try? PaddleOCRModelStore.verify(file: model, sha256: component.artifact.modelSHA256)) == true
                && (try? PaddleOCRModelStore.verify(file: config, sha256: component.artifact.configurationSHA256)) == true
        }
        if ready { validatedSelections.insert(selection) }
        return ready
    }

    public func downloadModels(
        progress: @Sendable (RecognitionModelProgress) -> Void = { _ in }
    ) async throws {
        try await downloadModels(mode: .structure, progress: progress)
    }

    public func downloadModels(
        mode: DocumentRecognitionMode,
        progress: @Sendable (RecognitionModelProgress) -> Void = { _ in }
    ) async throws {
        try await downloadModels(mode: mode, modelSize: .server, progress: progress)
    }

    public func downloadModels(
        mode: DocumentRecognitionMode,
        modelSize: DocumentRecognitionModelSize,
        progress: @Sendable (RecognitionModelProgress) -> Void = { _ in }
    ) async throws {
        engine = nil
        ocrEngines.removeAll()
        validatedSelections.removeAll()
        let components = Self.modelComponents(for: mode, modelSize: modelSize)
        for (index, component) in components.enumerated() {
            progress(.init(completed: index, total: components.count, name: component.title))
            _ = try await PaddleOCRModelStore.download(component.artifact, into: modelRoot)
        }
        validatedSelections.insert(.init(mode: mode, modelSize: mode == .ocr ? modelSize : .server))
        progress(.init(completed: components.count, total: components.count, name: "模型校验完成"))
    }

    public nonisolated static func modelComponents(for mode: DocumentRecognitionMode) -> [RecognitionModelComponent] {
        modelComponents(for: mode, modelSize: .server)
    }

    public nonisolated static func modelComponents(
        for mode: DocumentRecognitionMode,
        modelSize: DocumentRecognitionModelSize
    ) -> [RecognitionModelComponent] {
        switch mode {
        case .structure: modelComponents
        case .ocr: ocrModelComponents(for: modelSize)
        }
    }

    public nonisolated static func ocrModelComponents(
        for modelSize: DocumentRecognitionModelSize
    ) -> [RecognitionModelComponent] {
        switch modelSize {
        case .mobile:
            [
                .init(title: "PP-OCRv5 Mobile 文本检测", artifact: mobileDetectionArtifact),
                .init(title: "PP-OCRv5 Mobile 文本识别", artifact: mobileRecognitionArtifact),
            ]
        case .server:
            Array(modelComponents.prefix(2))
        }
    }

    public func analyze(
        documents: [URL],
        configuration: DocumentRecognitionConfiguration
    ) throws -> StructureBatchResult {
        guard !documents.isEmpty else { throw DocumentRecognitionError.noDocuments }
        if configuration.mode == .ocr,
           configuration.ocrModelSize == .mobile,
           configuration.ocrProvider == .coreML {
            throw DocumentRecognitionError.unsupportedOCRCombination
        }
        if let unsupported = documents.first(where: { !Self.accepts($0) }) {
            throw DocumentRecognitionError.unsupportedInput(unsupported.lastPathComponent)
        }
        guard modelsReady(mode: configuration.mode, modelSize: configuration.ocrModelSize) else {
            throw DocumentRecognitionError.modelsMissing
        }
        if configuration.mode == .ocr {
            return try analyzeOCR(documents: documents, configuration: configuration)
        }
        let engine = try engine ?? makeEngine()
        self.engine = engine
        return try engine.analyzeBatch(
            documentsAt: documents,
            options: configuration.structureOptions,
            maxConcurrentDocuments: configuration.normalizedConcurrency
        )
    }

    private func analyzeOCR(
        documents: [URL],
        configuration: DocumentRecognitionConfiguration
    ) throws -> StructureBatchResult {
        let key = OCRSessionKey(provider: configuration.ocrProvider, modelSize: configuration.ocrModelSize)
        let recognizer = try ocrEngines[key] ?? makeOCREngine(provider: key.provider, modelSize: key.modelSize)
        ocrEngines[key] = recognizer
        let batchStarted = ContinuousClock.now
        var results: [StructureDocumentResult] = []
        var itemSeconds: [Double] = []
        for source in documents {
            let started = ContinuousClock.now
            results.append(try recognizeOCRDocument(source, recognizer: recognizer))
            itemSeconds.append(Self.seconds(ContinuousClock.now - started))
        }
        let totalSeconds = Self.seconds(ContinuousClock.now - batchStarted)
        let sorted = itemSeconds.sorted()
        let metrics = StructureBatchMetrics(
            documentCount: documents.count,
            maxConcurrentDocuments: 1,
            totalSeconds: totalSeconds,
            throughputPerSecond: totalSeconds > 0 ? Double(documents.count) / totalSeconds : 0,
            p50Seconds: Self.percentile(sorted, 0.50),
            p95Seconds: Self.percentile(sorted, 0.95),
            itemSeconds: itemSeconds
        )
        return StructureBatchResult(documents: results, metrics: metrics)
    }

    private func makeOCREngine(
        provider: DocumentRecognitionProvider,
        modelSize: DocumentRecognitionModelSize
    ) throws -> OCRRecognizer {
        let artifacts = Self.ocrModelComponents(for: modelSize).map(\.artifact)
        let detection = modelFiles(artifacts[0])
        let recognition = modelFiles(artifacts[1])
        return try OCRRecognizer(
            models: OCRModelConfiguration(
                detectionModel: detection.model,
                recognitionModel: recognition.model,
                recognitionConfiguration: recognition.configuration
            ),
            executionProvider: provider.sdkProvider
        )
    }

    private func recognizeOCRDocument(_ source: URL, recognizer: OCRRecognizer) throws -> StructureDocumentResult {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNest-OCR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let images = try Self.pageImages(for: source, workspace: workspace)
        let pages = try images.enumerated().map { index, page in
            let result = try recognizer.recognize(imageAt: page.url)
            let confidence = result.lines.isEmpty
                ? 0
                : result.lines.map(\.confidence).reduce(0, +) / Float(result.lines.count)
            let block = StructureBlock(
                type: .text,
                label: "ocr_text",
                bounds: Bounds(x1: 0, y1: 0, x2: Float(page.width), y2: Float(page.height)),
                confidence: confidence,
                content: result.text,
                readingOrder: 0,
                ocrLines: result.lines
            )
            return StructurePageResult(
                pageIndex: index,
                width: page.width,
                height: page.height,
                orientationDegrees: 0,
                blocks: [block],
                overallOCR: result
            )
        }
        return StructureDocumentResult(source: source, pages: pages)
    }

    private struct OCRPageImage {
        let url: URL
        let width: Int
        let height: Int
    }

    private nonisolated static func pageImages(for source: URL, workspace: URL) throws -> [OCRPageImage] {
        guard source.pathExtension.lowercased() == "pdf" else {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
                throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent)
            }
            return [.init(url: source, width: width, height: height)]
        }
        guard let document = CGPDFDocument(source as CFURL) else {
            throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent)
        }
        guard document.numberOfPages > 0 else { return [] }
        return try (1 ... document.numberOfPages).map { pageNumber in
            guard let page = document.page(at: pageNumber) else {
                throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent)
            }
            let box = page.getBoxRect(.mediaBox)
            let scale = min(3, max(1.5, 2400 / max(box.width, box.height)))
            let width = max(1, Int((box.width * scale).rounded()))
            let height = max(1, Int((box.height * scale).rounded()))
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent) }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.concatenate(page.getDrawingTransform(
                .mediaBox,
                rect: CGRect(x: 0, y: 0, width: width, height: height),
                rotate: 0,
                preserveAspectRatio: true
            ))
            context.drawPDFPage(page)
            guard let image = context.makeImage() else {
                throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent)
            }
            let output = workspace.appendingPathComponent("page-\(pageNumber).png")
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw DocumentRecognitionError.unsupportedInput(source.lastPathComponent)
            }
            return .init(url: output, width: width, height: height)
        }
    }

    private func modelFiles(_ artifact: PaddleOCRModelArtifact) -> (model: URL, configuration: URL) {
        let directory = modelRoot.appendingPathComponent(artifact.name, isDirectory: true)
        return (
            directory.appendingPathComponent("inference.onnx"),
            directory.appendingPathComponent("inference.yml")
        )
    }

    private nonisolated static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private nonisolated static func modelArtifact(
        name: String,
        revision: String,
        modelSHA256: String,
        configurationSHA256: String
    ) -> PaddleOCRModelArtifact {
        let base = URL(string: "https://huggingface.co/PaddlePaddle/\(name)/resolve/\(revision)/")!
        return PaddleOCRModelArtifact(
            name: name,
            revision: revision,
            modelURL: base.appendingPathComponent("inference.onnx"),
            configurationURL: base.appendingPathComponent("inference.yml"),
            modelSHA256: modelSHA256,
            configurationSHA256: configurationSHA256
        )
    }

    private nonisolated static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let index = max(0, min(values.count - 1, Int(ceil(percentile * Double(values.count))) - 1))
        return values[index]
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
