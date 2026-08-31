import Foundation

public enum FileNestAutomationError: LocalizedError {
    case invalidArguments(String)
    case unknownTool(String)
    case confirmationRequired(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): message
        case .unknownTool(let name): "未知工具：\(name)"
        case .confirmationRequired(let name): "\(name) 会修改或移除文件，必须显式传入 confirm=true"
        }
    }
}

public enum FileNestAutomation {
    public static let toolNames = [
        "archive_list", "archive_create", "archive_extract", "hash_compute",
        "catalog_export", "files_copy", "files_rename", "files_trash",
        "file_extension_repair", "file_regex_copy", "file_sanitize_names",
        "image_process", "pdf_images_to_pdf", "pdf_merge", "pdf_split",
        "pdf_extract_regex", "pdf_signatures", "spreadsheet_group", "ncm_convert"
    ]

    public static func call(_ tool: String, arguments: [String: Any]) throws -> [String: Any] {
        switch tool {
        case "archive_list": return try archiveList(arguments)
        case "archive_create": return try archiveCreate(arguments)
        case "archive_extract": return try archiveExtract(arguments)
        case "hash_compute": return try hash(arguments)
        case "catalog_export": return try catalog(arguments)
        case "files_copy": return try workbookOperation(arguments, mode: .copy)
        case "files_rename": return try workbookOperation(arguments, mode: .rename)
        case "files_trash": return try workbookOperation(arguments, mode: .trash)
        case "file_extension_repair": return try fileTool(arguments, mode: .extensionRepair)
        case "file_regex_copy": return try fileTool(arguments, mode: .regexCopy)
        case "file_sanitize_names": return try fileTool(arguments, mode: .sanitizeNames)
        case "image_process": return try image(arguments)
        case "pdf_images_to_pdf": return try pdfImages(arguments)
        case "pdf_merge": return try pdfMerge(arguments)
        case "pdf_split": return try pdfSplit(arguments)
        case "pdf_extract_regex": return try pdfRegex(arguments)
        case "pdf_signatures": return try pdfSignatures(arguments)
        case "spreadsheet_group": return try spreadsheet(arguments)
        case "ncm_convert": return try ncm(arguments)
        default: throw FileNestAutomationError.unknownTool(tool)
        }
    }

    private static func archiveList(_ a: [String: Any]) throws -> [String: Any] {
        let entries = try ArchiveEngine.shared.list(archive: url(a, "archive"), password: string(a, "password", default: ""))
        return ["entries": entries.map { ["path": $0.path, "size": $0.size, "directory": $0.directory] }]
    }

    private static func archiveCreate(_ a: [String: Any]) throws -> [String: Any] {
        let inputs = try paths(a, "inputs")
        let output = try url(a, "output")
        guard let format = ArchiveFormat(rawValue: string(a, "format", default: "7z")) else {
            throw FileNestAutomationError.invalidArguments("format 必须是 7z、zip 或 tar")
        }
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ArchiveEngine.shared.compress(
            inputs: inputs, to: output, format: format,
            password: string(a, "password", default: ""),
            level: integer(a, "level", default: 6),
            dictionarySize: UInt64(max(0, integer(a, "dictionarySize", default: 0))),
            excludeMacOSMetadata: boolean(a, "excludeMacOSMetadata", default: true),
            volumeSize: UInt64(max(0, integer(a, "volumeSize", default: 0))),
            cancellation: ArchiveCancellation(), progress: { _ in }
        )
        return ["output": output.path]
    }

    private static func archiveExtract(_ a: [String: Any]) throws -> [String: Any] {
        let output = try url(a, "output")
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw FileNestAutomationError.invalidArguments("解压目标已存在：\(output.path)")
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ArchiveEngine.shared.extract(
            archive: url(a, "archive"), to: output,
            password: string(a, "password", default: ""),
            cancellation: ArchiveCancellation(), progress: { _ in }
        )
        return ["output": output.path]
    }

    private static func hash(_ a: [String: Any]) throws -> [String: Any] {
        let raw = string(a, "algorithm", default: "SHA-256").uppercased()
        guard let algorithm = HashAlgorithm.allCases.first(where: { $0.rawValue == raw }) else {
            throw FileNestAutomationError.invalidArguments("不支持的 Hash 算法")
        }
        let files = try paths(a, "files")
        return ["algorithm": algorithm.rawValue, "files": try files.map {
            ["path": $0.path, "digest": try FileHashService.digest(file: $0, algorithm: algorithm)]
        }]
    }

    private static func catalog(_ a: [String: Any]) throws -> [String: Any] {
        let output = try url(a, "output")
        let entries = try FileCatalogService.export(directory: url(a, "directory"), to: output)
        return ["output": output.path, "count": entries.count]
    }

    private enum WorkbookMode { case copy, rename, trash }
    private static func workbookOperation(_ a: [String: Any], mode: WorkbookMode) throws -> [String: Any] {
        if mode != .copy { try confirmed(a, mode == .rename ? "批量重命名" : "移到废纸篓") }
        let sheet = try XLSXDocument.read(from: url(a, "workbook"))
        func column(_ key: String) throws -> XLSXColumn {
            let value = string(a, key)
            if let index = Int(value), let found = sheet.columns.first(where: { $0.index == index }) { return found }
            guard let found = sheet.columns.first(where: { $0.title == value }) else {
                throw FileNestAutomationError.invalidArguments("找不到列：\(value)")
            }
            return found
        }
        let operations: [FileOperationPreview]
        switch mode {
        case .copy: operations = FileOperationService.copyPreview(sheet: sheet, sourceColumn: try column("sourceColumn"), destinationColumn: try column("destinationColumn"))
        case .rename: operations = FileOperationService.renamePreview(sheet: sheet, pathColumn: try column("pathColumn"), nameColumn: try column("nameColumn"))
        case .trash: operations = FileOperationService.trashPreview(sheet: sheet, pathColumn: try column("pathColumn"))
        }
        let result: ([FileOperationPreview], FileOperationSummary) = switch mode {
        case .copy: FileOperationService.executeCopies(operations)
        case .rename: FileOperationService.executeRenames(operations)
        case .trash: FileOperationService.executeTrash(operations)
        }
        return ["total": result.1.total, "succeeded": result.1.succeeded, "failed": result.1.failed]
    }

    private enum FileToolMode { case extensionRepair, regexCopy, sanitizeNames }
    private static func fileTool(_ a: [String: Any], mode: FileToolMode) throws -> [String: Any] {
        if mode != .regexCopy { try confirmed(a, mode == .extensionRepair ? "扩展名修复" : "名称清理") }
        let root = try url(a, "root")
        let operations: [BatchFileOperation]
        switch mode {
        case .extensionRepair: operations = try FileToolService.extensionRepairPreview(in: root)
        case .regexCopy: operations = try FileToolService.regexCopyPreview(in: root, outputRoot: url(a, "output"), pattern: string(a, "pattern"), replacement: string(a, "replacement"))
        case .sanitizeNames: operations = try FileToolService.sanitizePreview(in: root)
        }
        let result = mode == .regexCopy ? FileToolService.executeCopies(operations) : FileToolService.executeMoves(operations)
        return ["total": result.1.total, "succeeded": result.1.succeeded, "failed": result.1.failed]
    }

    private static func image(_ a: [String: Any]) throws -> [String: Any] {
        let replace = boolean(a, "replaceOriginals", default: false)
        if replace { try confirmed(a, "替换原图") }
        let formatName = string(a, "format", default: "keep").lowercased()
        let formatAliases: [String: ImageOutputFormat] = [
            "keep": .keep, "保持原格式": .keep, "jpeg": .jpeg, "jpg": .jpeg,
            "png": .png, "heic": .heic, "webp": .webp,
        ]
        guard let format = formatAliases[formatName] else {
            throw FileNestAutomationError.invalidArguments("无效图片格式")
        }
        let quality = double(a, "quality", default: 0.82)
        guard (0.01 ... 1).contains(quality) else {
            throw FileNestAutomationError.invalidArguments("quality 必须在 0.01 到 1 之间")
        }
        let results = try ImageProcessingService.processDirectory(
            url(a, "root"), outputRoot: optionalURL(a, "output"), recursively: boolean(a, "recursive", default: true),
            options: .init(maximumWidth: integer(a, "maximumWidth", default: 0), maximumHeight: integer(a, "maximumHeight", default: 0), quality: quality, format: format, replaceOriginals: replace)
        )
        return ["total": results.count, "succeeded": results.filter { $0.error == nil }.count, "failed": results.filter { $0.error != nil }.count]
    }

    private static func pdfImages(_ a: [String: Any]) throws -> [String: Any] {
        let results = try PDFToolService.convertImagesToPDF(in: url(a, "root"), outputRoot: optionalURL(a, "output"), recursively: boolean(a, "recursive", default: true))
        return batchPDF(results)
    }
    private static func pdfMerge(_ a: [String: Any]) throws -> [String: Any] {
        if let files = a["files"] as? [String] {
            let output = try url(a, "output")
            try PDFToolService.merge(files: files.map { URL(fileURLWithPath: $0) }, to: output)
            return ["output": output.path]
        }
        return batchPDF(try PDFToolService.batchMergeChildDirectories(root: url(a, "root"), outputRoot: optionalURL(a, "output"), sortConfiguration: string(a, "sortConfiguration", default: "")))
    }
    private static func pdfSplit(_ a: [String: Any]) throws -> [String: Any] {
        let outputs = try PDFToolService.splitPDF(url(a, "source"), keyword: string(a, "keyword"), outputRoot: url(a, "output"))
        return ["outputs": outputs.map(\.path)]
    }
    private static func pdfRegex(_ a: [String: Any]) throws -> [String: Any] {
        let rows = try PDFToolService.extractRegex(from: paths(a, "files"), pattern: string(a, "pattern"))
        let output = try url(a, "output")
        try XLSXDocument.write(headers: ["文件路径", "文件名", "提取内容"], rows: rows.map(\.spreadsheetRow), to: output)
        return ["output": output.path, "count": rows.count]
    }
    private static func pdfSignatures(_ a: [String: Any]) throws -> [String: Any] {
        let signatures = try PDFSignatureService.extractSignatures(from: url(a, "file"))
        return ["count": signatures.count, "signatures": signatures.map {
            [
                "fieldName": $0.fieldName,
                "signer": $0.signerCommonName,
                "organization": $0.signerOrganization,
                "serialNumber": $0.certificateSerialNumber,
                "digestMatches": $0.protectedContentDigestMatches,
                "trusted": $0.certificateTrustedBySystem,
                "coversWholeDocument": $0.coversWholeDocument,
            ]
        }]
    }
    private static func spreadsheet(_ a: [String: Any]) throws -> [String: Any] {
        let sheet = try XLSXDocument.read(from: url(a, "workbook"))
        let name = string(a, "groupingColumn")
        guard let column = sheet.columns.first(where: { $0.title == name || String($0.index) == name }) else { throw FileNestAutomationError.invalidArguments("找不到分组列") }
        let rows = try SpreadsheetToolService.groupedRows(sheet: sheet, groupingColumn: column)
        let output = try url(a, "output")
        try XLSXDocument.write(headers: sheet.columns.map(\.title), rows: rows, to: output)
        return ["output": output.path, "count": rows.count]
    }
    private static func ncm(_ a: [String: Any]) throws -> [String: Any] {
        let output = try NCMConversionService.convert(source: url(a, "source"), destinationDirectory: url(a, "output"), cancellation: NCMCancellation(), progress: { _ in })
        return ["output": output.url.path]
    }

    private static func batchPDF(_ results: [PDFBatchResult]) -> [String: Any] { ["total": results.count, "succeeded": results.filter { $0.error == nil }.count, "failed": results.filter { $0.error != nil }.count] }
    private static func confirmed(_ a: [String: Any], _ name: String) throws { if !boolean(a, "confirm", default: false) { throw FileNestAutomationError.confirmationRequired(name) } }
    private static func string(_ a: [String: Any], _ key: String, default value: String? = nil) -> String { (a[key] as? String) ?? value ?? "" }
    private static func integer(_ a: [String: Any], _ key: String, default value: Int) -> Int { (a[key] as? Int) ?? (a[key] as? NSNumber)?.intValue ?? value }
    private static func double(_ a: [String: Any], _ key: String, default value: Double) -> Double { (a[key] as? Double) ?? (a[key] as? NSNumber)?.doubleValue ?? value }
    private static func boolean(_ a: [String: Any], _ key: String, default value: Bool) -> Bool { (a[key] as? Bool) ?? value }
    private static func url(_ a: [String: Any], _ key: String) throws -> URL { guard let value = a[key] as? String, !value.isEmpty else { throw FileNestAutomationError.invalidArguments("缺少参数：\(key)") }; return URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL }
    private static func optionalURL(_ a: [String: Any], _ key: String) -> URL? { guard let value = a[key] as? String, !value.isEmpty else { return nil }; return URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL }
    private static func paths(_ a: [String: Any], _ key: String) throws -> [URL] { guard let values = a[key] as? [String], !values.isEmpty else { throw FileNestAutomationError.invalidArguments("缺少参数：\(key)") }; return values.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL } }
}
