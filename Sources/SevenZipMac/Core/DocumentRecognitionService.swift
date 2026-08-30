import Foundation
import PaddleOCRCoreML

enum DocumentRecognitionService {
    static var sdkVersion: String { PaddleOCRCoreML.version }

    static func makeOCRRecognizer(
        models: OCRModelConfiguration,
        executionProvider: PaddleOCRExecutionProvider = .coreML
    ) throws -> OCRRecognizer {
        try OCRRecognizer(models: models, executionProvider: executionProvider)
    }

    static func makeLayoutAnalyzer(
        model: URL,
        executionProvider: PaddleOCRExecutionProvider = .coreML
    ) throws -> LayoutAnalyzer {
        try LayoutAnalyzer(model: model, executionProvider: executionProvider)
    }

    static func makeTableStructureRecognizer(
        model: URL,
        configuration: URL,
        executionProvider: PaddleOCRExecutionProvider = .coreML
    ) throws -> TableStructureRecognizer {
        try TableStructureRecognizer(
            model: model,
            configuration: configuration,
            executionProvider: executionProvider
        )
    }
}
