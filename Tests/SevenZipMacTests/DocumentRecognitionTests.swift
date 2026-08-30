import FileNestOCRCore
import Foundation
import PaddleOCRCoreML
import Testing

@Suite("Native document recognition integration")
struct DocumentRecognitionTests {
    @Test("SDK, model catalog and supported inputs are wired")
    func sdkAndCatalog() {
        #expect(DocumentRecognitionService.sdkVersion == "0.3.0")
        #expect(DocumentRecognitionService.modelComponents.count == 11)
        #expect(Set(DocumentRecognitionService.modelComponents.map(\.artifact.name)).count == 11)
        #expect(DocumentRecognitionService.modelComponents.allSatisfy { $0.artifact.modelSHA256.count == 64 })
        #expect(DocumentRecognitionService.accepts(URL(fileURLWithPath: "/tmp/a.PDF")))
        #expect(DocumentRecognitionService.accepts(URL(fileURLWithPath: "/tmp/a.webp")))
        #expect(!DocumentRecognitionService.accepts(URL(fileURLWithPath: "/tmp/a.txt")))
    }

    @Test("Batch concurrency is clamped to the measured safe range")
    func concurrencyClamp() {
        #expect(DocumentRecognitionConfiguration(maxConcurrentDocuments: -1).normalizedConcurrency == 1)
        #expect(DocumentRecognitionConfiguration(maxConcurrentDocuments: 2).normalizedConcurrency == 2)
        #expect(DocumentRecognitionConfiguration(maxConcurrentDocuments: 99).normalizedConcurrency == 4)
    }

    @Test("An empty model directory is not reported ready")
    func missingModels() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DocumentRecognitionService(modelRoot: root)
        #expect(await !service.modelsReady())
    }

    @Test("Every structured export format writes a usable file")
    func exports() throws {
        let document = try fixtureDocument()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for format in DocumentExportFormat.allCases {
            let output = root.appendingPathComponent("result.\(format.fileExtension)")
            try DocumentRecognitionService.export(document, format: format, to: output)
            let data = try Data(contentsOf: output)
            #expect(!data.isEmpty)
            if format == .docx || format == .xlsx { #expect(Array(data.prefix(2)) == [0x50, 0x4b]) }
        }
        #expect(try String(contentsOf: root.appendingPathComponent("result.md"), encoding: .utf8).contains("示例标题"))
        #expect(try String(contentsOf: root.appendingPathComponent("result.html"), encoding: .utf8).contains("<h1>"))
        let decoded = try JSONDecoder().decode(
            StructureDocumentResult.self,
            from: Data(contentsOf: root.appendingPathComponent("result.json"))
        )
        #expect(decoded.pages.first?.blocks.first?.content == "示例标题")
    }

    private func fixtureDocument() throws -> StructureDocumentResult {
        let object: [String: Any] = [
            "source": "file:///tmp/source.png",
            "pages": [[
                "pageIndex": 0,
                "width": 1000,
                "height": 800,
                "orientationDegrees": 0,
                "blocks": [[
                    "type": "title",
                    "label": "doc_title",
                    "bounds": ["x1": 10, "y1": 10, "x2": 900, "y2": 100],
                    "confidence": 0.98,
                    "content": "示例标题",
                    "readingOrder": 0,
                    "ocrLines": [],
                ]],
                "overallOCR": ["lines": []],
            ]],
        ]
        return try JSONDecoder().decode(
            StructureDocumentResult.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
