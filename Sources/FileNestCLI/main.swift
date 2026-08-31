import Darwin
import FileNestKit
import FileNestOCRCore
import Foundation
import PaddleOCRCoreML

private enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): message
        }
    }
}

private struct Arguments {
    var values: [String: [String]] = [:]
    var flags: Set<String> = []
    var positionals: [String] = []

    init(_ arguments: [String]) throws {
        var index = 0
        let valueOptions: Set<String> = ["input", "output", "format", "jobs", "model-dir", "provider", "model-size", "engine", "arguments"]
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let key = String(argument.dropFirst(2))
                if valueOptions.contains(key) {
                    guard index + 1 < arguments.count else { throw CLIError.usage("--\(key) 缺少参数") }
                    values[key, default: []].append(arguments[index + 1])
                    index += 2
                } else {
                    flags.insert(key)
                    index += 1
                }
            } else {
                positionals.append(argument)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? { values[key]?.last }
}

@main
private struct FileNestCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            writeJSON(["ok": false, "error": error.localizedDescription], to: .standardError)
            exit(2)
        }
    }

    private static func run(_ raw: [String]) async throws {
        guard let command = raw.first, command != "help", command != "--help" else {
            print(usage)
            return
        }
        let arguments = try Arguments(Array(raw.dropFirst()))
        let modelRoot = arguments.value("model-dir").map(fileURL)
            ?? DocumentRecognitionService.defaultModelRoot()
        let service = DocumentRecognitionService(modelRoot: modelRoot)

        switch command {
        case "models":
            try await models(arguments, service: service, root: modelRoot)
        case "recognize":
            try await recognize(arguments, service: service)
        case "tools":
            writeJSON(["ok": true, "tools": FileNestAutomation.toolNames])
        case "run":
            guard let tool = arguments.positionals.first else { throw CLIError.usage("run 需要工具名称") }
            let json = arguments.value("arguments") ?? "{}"
            guard let data = json.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CLIError.usage("--arguments 必须是 JSON object")
            }
            writeJSON(["ok": true, "result": try FileNestAutomation.call(tool, arguments: object)])
        case "version":
            writeJSON(["ok": true, "sdkVersion": DocumentRecognitionService.sdkVersion])
        default:
            throw CLIError.usage("未知命令：\(command)\n\(usage)")
        }
    }

    private static func models(
        _ arguments: Arguments,
        service: DocumentRecognitionService,
        root: URL
    ) async throws {
        let action = arguments.positionals.first ?? "status"
        switch action {
        case "status":
            let mode = try recognitionMode(arguments)
            let modelSize = try recognitionModelSize(arguments)
            let ready = await service.modelsReady(mode: mode, modelSize: modelSize)
            writeJSON([
                "ok": true,
                "ready": ready,
                "mode": mode.rawValue,
                "modelSize": recognitionModelLabel(mode: mode, modelSize: modelSize),
                "modelCount": DocumentRecognitionService.modelComponents(for: mode, modelSize: modelSize).count,
                "modelDirectory": root.path,
                "sdkVersion": DocumentRecognitionService.sdkVersion,
            ])
        case "download":
            let mode = try recognitionMode(arguments)
            let modelSize = try recognitionModelSize(arguments)
            try await service.downloadModels(mode: mode, modelSize: modelSize) { progress in
                writeJSON([
                    "event": "model-progress",
                    "completed": progress.completed,
                    "total": progress.total,
                    "name": progress.name,
                ], to: .standardError)
            }
            writeJSON([
                "ok": true,
                "ready": true,
                "mode": mode.rawValue,
                "modelSize": recognitionModelLabel(mode: mode, modelSize: modelSize),
                "modelDirectory": root.path,
            ])
        default:
            throw CLIError.usage("models 仅支持 status 或 download")
        }
    }

    private static func recognize(
        _ arguments: Arguments,
        service: DocumentRecognitionService
    ) async throws {
        let inputValues = arguments.values["input", default: []] + arguments.positionals
        guard !inputValues.isEmpty else { throw CLIError.usage("recognize 至少需要一个 --input") }
        guard let outputValue = arguments.value("output") else { throw CLIError.usage("recognize 需要 --output") }
        let formatName = (arguments.value("format") ?? "json").lowercased()
        guard let format = DocumentExportFormat.allCases.first(where: {
            $0.fileExtension == formatName || $0.rawValue.lowercased() == formatName
        }) else { throw CLIError.usage("不支持的输出格式：\(formatName)") }
        let jobs = Int(arguments.value("jobs") ?? "2") ?? 2
        let inputs = try discover(inputValues.map(fileURL))
        guard !inputs.isEmpty else { throw CLIError.usage("没有找到支持的图片或 PDF") }

        let output = fileURL(outputValue)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let mode = try recognitionMode(arguments)
        let modelSize = try recognitionModelSize(arguments)
        let provider = try recognitionProvider(arguments, modelSize: modelSize)
        let configuration = DocumentRecognitionConfiguration(
            mode: mode,
            ocrProvider: provider,
            ocrModelSize: modelSize,
            maxConcurrentDocuments: jobs,
            classifyOrientation: !arguments.flags.contains("no-orientation"),
            unwarpDocument: arguments.flags.contains("unwarp"),
            recognizeTables: !arguments.flags.contains("no-tables"),
            recognizeFormulae: !arguments.flags.contains("no-formula"),
            recognizeCharts: arguments.flags.contains("charts")
        )
        let batch = try await service.analyze(documents: inputs, configuration: configuration)
        var items: [[String: Any]] = []
        for (index, document) in batch.documents.enumerated() {
            let destination = uniqueDestination(
                directory: output,
                stem: document.source.deletingPathExtension().lastPathComponent,
                extension: format.fileExtension
            )
            try DocumentRecognitionService.export(document, format: format, to: destination)
            items.append([
                "input": document.source.path,
                "output": destination.path,
                "seconds": batch.metrics.itemSeconds[index],
                "pages": document.pages.count,
            ])
        }
        writeJSON([
            "ok": true,
            "format": format.fileExtension,
            "mode": mode.rawValue,
            "provider": recognitionProviderLabel(mode: mode, provider: provider),
            "modelSize": recognitionModelLabel(mode: mode, modelSize: modelSize),
            "documents": items,
            "metrics": [
                "count": batch.metrics.documentCount,
                "jobs": batch.metrics.maxConcurrentDocuments,
                "totalSeconds": batch.metrics.totalSeconds,
                "throughputPerSecond": batch.metrics.throughputPerSecond,
                "p50Seconds": batch.metrics.p50Seconds,
                "p95Seconds": batch.metrics.p95Seconds,
            ],
        ])
    }

    private static func discover(_ urls: [URL]) throws -> [URL] {
        var results: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw CLIError.usage("输入不存在：\(url.path)")
            }
            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let candidate = enumerator?.nextObject() as? URL {
                    let values = try? candidate.resourceValues(forKeys: Set(keys))
                    if values?.isRegularFile == true, DocumentRecognitionService.accepts(candidate) {
                        results.append(candidate.standardizedFileURL)
                    }
                }
            } else if DocumentRecognitionService.accepts(url) {
                results.append(url.standardizedFileURL)
            } else {
                throw DocumentRecognitionError.unsupportedInput(url.lastPathComponent)
            }
        }
        return Array(Set(results)).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func uniqueDestination(directory: URL, stem: String, extension ext: String) -> URL {
        var destination = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(stem)_\(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return destination
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func recognitionProvider(
        _ arguments: Arguments,
        modelSize: DocumentRecognitionModelSize
    ) throws -> DocumentRecognitionProvider {
        let defaultProvider: DocumentRecognitionProvider = .coreML
        let value = (arguments.value("provider") ?? defaultProvider.rawValue).lowercased()
        guard let provider = DocumentRecognitionProvider(rawValue: value) else {
            throw CLIError.usage("--provider 仅支持 coreml 或 cpu")
        }
        return provider
    }

    private static func recognitionMode(_ arguments: Arguments) throws -> DocumentRecognitionMode {
        guard let value = arguments.value("engine")?.lowercased() else {
            return arguments.flags.contains("ocr-only") ? .ocr : .structure
        }
        switch value {
        case "structure": return .structure
        case "paddle", "ocr": return .ocr
        case "vision": return .vision
        default: throw CLIError.usage("--engine 仅支持 structure、paddle 或 vision")
        }
    }

    private static func recognitionProviderLabel(
        mode: DocumentRecognitionMode,
        provider: DocumentRecognitionProvider
    ) -> String {
        switch mode {
        case .structure: DocumentRecognitionProvider.cpu.rawValue
        case .ocr: provider.rawValue
        case .vision: "vision-accurate"
        }
    }

    private static func recognitionModelLabel(
        mode: DocumentRecognitionMode,
        modelSize: DocumentRecognitionModelSize
    ) -> String {
        switch mode {
        case .structure: DocumentRecognitionModelSize.server.rawValue
        case .ocr: modelSize.rawValue
        case .vision: "system"
        }
    }

    private static func recognitionModelSize(_ arguments: Arguments) throws -> DocumentRecognitionModelSize {
        let value = (arguments.value("model-size") ?? DocumentRecognitionModelSize.server.rawValue).lowercased()
        guard let modelSize = DocumentRecognitionModelSize(rawValue: value) else {
            throw CLIError.usage("--model-size 仅支持 mobile 或 server")
        }
        return modelSize
    }

    private static func writeJSON(_ object: Any, to handle: FileHandle = .standardOutput) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        handle.write(data)
        handle.write(Data([0x0a]))
    }

    private static let usage = """
    FileNest 全功能原生 CLI（无 Python、无 7z 子进程）

      filenest-cli version
      filenest-cli tools
      filenest-cli run TOOL --arguments '{"key":"value"}'
      filenest-cli models status [--model-dir DIR] [--engine structure|paddle|vision]
      filenest-cli models download [--model-dir DIR] [--engine structure|paddle|vision]
      filenest-cli recognize --input FILE_OR_DIR [--input FILE] --output DIR
          [--format json|markdown|html|docx|xlsx] [--jobs 1...4]
          [--unwarp] [--charts] [--no-orientation] [--no-tables] [--no-formula]
          [--engine structure|paddle|vision] [--model-size mobile|server] [--provider coreml|cpu]
      # --ocr-only 保留为 --engine paddle 的兼容别名；Vision 固定 accurate 且无需模型
      # 默认 CoreML；Mobile 自动使用精确兼容模式，避免动态 CoreML 子图产生乱码

    stdout 只输出最终 JSON；下载进度与错误 JSON 输出到 stderr，适合 MCP/自动化调用。
    """
}
