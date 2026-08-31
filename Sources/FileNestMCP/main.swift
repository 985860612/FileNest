import FileNestKit
import FileNestOCRCore
import Foundation
import PaddleOCRCoreML

private enum MCPError: LocalizedError {
    case invalidRequest(String)
    var errorDescription: String? { if case .invalidRequest(let value) = self { return value }; return nil }
}

@main
@MainActor
struct FileNestMCP {
    static func main() async {
        while let line = readLine() {
            guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
            do {
                guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any], let method = request["method"] as? String else { throw MCPError.invalidRequest("无效 JSON-RPC 请求") }
                if method.hasPrefix("notifications/") { continue }
                let result = try await handle(method, params: request["params"] as? [String: Any] ?? [:])
                send(["jsonrpc": "2.0", "id": request["id"] ?? NSNull(), "result": result])
            } catch {
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                send(["jsonrpc": "2.0", "id": object?["id"] ?? NSNull(), "error": ["code": -32603, "message": error.localizedDescription]])
            }
        }
    }

    private static func handle(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "initialize": return ["protocolVersion": "2025-03-26", "capabilities": ["tools": ["listChanged": false]], "serverInfo": ["name": "filenest-mcp", "version": "0.3.0"]]
        case "ping": return [:]
        case "tools/list": return ["tools": toolDefinitions]
        case "tools/call":
            guard let name = params["name"] as? String else { throw MCPError.invalidRequest("tools/call 缺少 name") }
            do {
                let result = try await call(name, arguments: params["arguments"] as? [String: Any] ?? [:])
                return ["content": [["type": "text", "text": jsonText(result)]], "isError": false]
            } catch {
                return ["content": [["type": "text", "text": jsonText(["ok": false, "error": error.localizedDescription])]], "isError": true]
            }
        default: throw MCPError.invalidRequest("不支持的方法：\(method)")
        }
    }

    private static func call(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "document_models_status":
            let root = modelRoot(arguments), service = DocumentRecognitionService(modelRoot: root)
            return ["ready": await service.modelsReady(), "modelDirectory": root.path, "modelCount": DocumentRecognitionService.modelComponents.count]
        case "document_models_download":
            let root = modelRoot(arguments), service = DocumentRecognitionService(modelRoot: root)
            try await service.downloadModels()
            return ["ready": true, "modelDirectory": root.path]
        case "document_recognize": return try await recognize(arguments)
        default: return try FileNestAutomation.call(name, arguments: arguments)
        }
    }

    private static func recognize(_ a: [String: Any]) async throws -> [String: Any] {
        guard let inputPaths = a["inputs"] as? [String], !inputPaths.isEmpty, let outputPath = a["output"] as? String else { throw MCPError.invalidRequest("document_recognize 需要 inputs 和 output") }
        let sources = inputPaths.map(fileURL), output = fileURL(outputPath)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let formatName = (a["format"] as? String ?? "json").lowercased()
        guard let format = DocumentExportFormat.allCases.first(where: { $0.fileExtension == formatName || $0.rawValue.lowercased() == formatName }) else { throw MCPError.invalidRequest("无效输出格式") }
        let service = DocumentRecognitionService(modelRoot: modelRoot(a))
        let batch = try await service.analyze(documents: sources, configuration: .init(maxConcurrentDocuments: (a["jobs"] as? NSNumber)?.intValue ?? 2, classifyOrientation: a["orientation"] as? Bool ?? true, unwarpDocument: a["unwarp"] as? Bool ?? false, recognizeTables: a["tables"] as? Bool ?? true, recognizeFormulae: a["formulae"] as? Bool ?? true, recognizeCharts: a["charts"] as? Bool ?? false))
        var outputs: [[String: Any]] = []
        for (index, document) in batch.documents.enumerated() {
            let destination = unique(in: output, stem: document.source.deletingPathExtension().lastPathComponent, ext: format.fileExtension)
            try DocumentRecognitionService.export(document, format: format, to: destination)
            outputs.append(["input": document.source.path, "output": destination.path, "seconds": batch.metrics.itemSeconds[index]])
        }
        return ["documents": outputs, "metrics": ["totalSeconds": batch.metrics.totalSeconds, "throughputPerSecond": batch.metrics.throughputPerSecond, "p50Seconds": batch.metrics.p50Seconds, "p95Seconds": batch.metrics.p95Seconds]]
    }

    private static var toolDefinitions: [[String: Any]] {
        let path = property("string", "绝对路径或含 ~ 的本地路径")
        let paths = property("array", "非空路径列表", items: ["type": "string"])
        let confirm = property("boolean", "确认执行会修改或移除文件的操作，必须为 true")
        return [
            tool("archive_list", "列出归档内容", required: ["archive"], ["archive": path, "password": property("string", "密码，可省略")]),
            tool("archive_create", "使用进程内 7-Zip SDK 创建 7z、ZIP 或 TAR", required: ["inputs", "output"], [
                "inputs": paths, "output": path, "format": enumProperty(["7z", "zip", "tar"]), "password": property("string"),
                "level": property("integer", "压缩等级 0...9"), "dictionarySize": property("integer", "字典字节数，0 为自动"),
                "excludeMacOSMetadata": property("boolean"), "volumeSize": property("integer", "分卷字节数，0 为不分卷"),
            ]),
            tool("archive_extract", "安全解压归档并阻止路径穿越", required: ["archive", "output"], ["archive": path, "output": path, "password": property("string")]),
            tool("hash_compute", "计算一个或多个文件的 Hash", required: ["files"], ["files": paths, "algorithm": enumProperty(["MD5", "SHA-1", "SHA-256", "SHA-512"])]),
            tool("catalog_export", "把目录内容导出到 XLSX", required: ["directory", "output"], ["directory": path, "output": path]),
            tool("files_copy", "按 XLSX 的源路径列和目标路径列批量复制", required: ["workbook", "sourceColumn", "destinationColumn"], workbookProperties(path: path)),
            tool("files_rename", "按 XLSX 批量重命名；会修改文件，要求 confirm=true", required: ["workbook", "pathColumn", "nameColumn", "confirm"], ["workbook": path, "pathColumn": property("string"), "nameColumn": property("string"), "confirm": confirm]),
            tool("files_trash", "按 XLSX 把文件移到废纸篓；要求 confirm=true", required: ["workbook", "pathColumn", "confirm"], ["workbook": path, "pathColumn": property("string"), "confirm": confirm]),
            tool("file_extension_repair", "按文件内容修复扩展名；要求 confirm=true", required: ["root", "confirm"], ["root": path, "confirm": confirm]),
            tool("file_regex_copy", "用正则生成相对路径并批量复制", required: ["root", "output", "pattern", "replacement"], ["root": path, "output": path, "pattern": property("string"), "replacement": property("string")]),
            tool("file_sanitize_names", "清理不兼容文件名；要求 confirm=true", required: ["root", "confirm"], ["root": path, "confirm": confirm]),
            tool("image_process", "批量缩放并转换 JPEG、PNG、HEIC、WebP", required: ["root"], [
                "root": path, "output": path, "recursive": property("boolean"), "maximumWidth": property("integer"), "maximumHeight": property("integer"),
                "quality": property("number", "0.01...1"), "format": enumProperty(["keep", "jpeg", "png", "heic", "webp"]),
                "replaceOriginals": property("boolean"), "confirm": confirm,
            ]),
            tool("pdf_images_to_pdf", "递归把图片目录转换为 PDF", required: ["root"], ["root": path, "output": path, "recursive": property("boolean")]),
            tool("pdf_merge", "合并 files 到 output，或批量合并 root 的子目录", required: [], ["files": paths, "root": path, "output": path, "sortConfiguration": property("string")]),
            tool("pdf_split", "按关键字所在页拆分 PDF", required: ["source", "keyword", "output"], ["source": path, "keyword": property("string"), "output": path]),
            tool("pdf_extract_regex", "从 PDF 正则提取文本并写入 XLSX", required: ["files", "pattern", "output"], ["files": paths, "pattern": property("string"), "output": path]),
            tool("pdf_signatures", "提取并验证 PDF 数字签名", required: ["file"], ["file": path]),
            tool("spreadsheet_group", "按指定列分组，将其他列去重合并", required: ["workbook", "groupingColumn", "output"], ["workbook": path, "groupingColumn": property("string", "列标题或从 1 开始的列号"), "output": path]),
            tool("ncm_convert", "恢复 NCM 音频到目标目录", required: ["source", "output"], ["source": path, "output": path]),
            tool("document_models_status", "检查 PP-StructureV3 模型是否就绪", required: [], ["modelDirectory": path]),
            tool("document_models_download", "下载并校验 PP-StructureV3 模型", required: [], ["modelDirectory": path]),
            tool("document_recognize", "批量结构化识别图片或 PDF", required: ["inputs", "output"], [
                "inputs": paths, "output": path, "modelDirectory": path,
                "format": enumProperty(["json", "markdown", "html", "docx", "xlsx"]), "jobs": property("integer", "并发文档数"),
                "orientation": property("boolean"), "unwarp": property("boolean"), "tables": property("boolean"),
                "formulae": property("boolean"), "charts": property("boolean"),
            ]),
        ]
    }

    private static func tool(_ name: String, _ description: String, required: [String], _ properties: [String: Any]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    private static func property(_ type: String, _ description: String? = nil, items: [String: Any]? = nil) -> [String: Any] {
        var value: [String: Any] = ["type": type]
        if let description { value["description"] = description }
        if let items { value["items"] = items }
        return value
    }

    private static func enumProperty(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }

    private static func workbookProperties(path: [String: Any]) -> [String: Any] {
        ["workbook": path, "sourceColumn": property("string"), "destinationColumn": property("string")]
    }

    private static func modelRoot(_ a: [String: Any]) -> URL { (a["modelDirectory"] as? String).map(fileURL) ?? DocumentRecognitionService.defaultModelRoot() }
    private static func fileURL(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL }
    private static func unique(in directory: URL, stem: String, ext: String) -> URL { var value = directory.appendingPathComponent(stem).appendingPathExtension(ext); var index = 2; while FileManager.default.fileExists(atPath: value.path) { value = directory.appendingPathComponent("\(stem)_\(index)").appendingPathExtension(ext); index += 1 }; return value }
    private static func jsonText(_ object: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "{}" }; return text }
    private static func send(_ object: Any) { guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }; FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([0x0a])) }
}
