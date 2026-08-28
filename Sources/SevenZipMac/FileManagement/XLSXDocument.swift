import Foundation

enum XLSXDocument {
    static func read(from url: URL, engine: ArchiveEngine = .shared) throws -> XLSXSheet {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("SevenZipMac-XLSX-\(UUID().uuidString)", isDirectory: true)
        let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        do {
            try engine.extract(
                archive: url,
                to: extracted,
                password: "",
                cancellation: ArchiveCancellation(),
                progress: { _ in }
            )
            return try readExtractedWorkbook(at: extracted)
        } catch let error as FileManagementError {
            throw error
        } catch {
            throw FileManagementError.invalidWorkbook(error.localizedDescription)
        }
    }

    static func write(
        headers: [String],
        rows: [[String]],
        to destination: URL,
        engine: ArchiveEngine = .shared
    ) throws {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("SevenZipMac-XLSX-\(UUID().uuidString)", isDirectory: true)
        let source = workspace.appendingPathComponent("contents", isDirectory: true)
        let temporaryArchive = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).xlsx")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspace)
            try? fileManager.removeItem(at: temporaryArchive)
        }

        try createPackage(headers: headers, rows: rows, at: source)
        let inputs = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        try engine.compress(
            inputs: inputs,
            to: temporaryArchive,
            format: .zip,
            password: "",
            level: 5,
            dictionarySize: 0,
            volumeSize: 0,
            cancellation: ArchiveCancellation(),
            progress: { _ in }
        )
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryArchive)
        } else {
            try fileManager.moveItem(at: temporaryArchive, to: destination)
        }
    }

    static func readExtractedWorkbook(at root: URL) throws -> XLSXSheet {
        let fileManager = FileManager.default
        let sharedStringsURL = root.appendingPathComponent("xl/sharedStrings.xml")
        let sharedStrings: [String]
        if fileManager.fileExists(atPath: sharedStringsURL.path) {
            sharedStrings = try SharedStringsParser.parse(Data(contentsOf: sharedStringsURL))
        } else {
            sharedStrings = []
        }

        let sheetURL = try firstWorksheetURL(in: root)
        let allRows = try WorksheetParser.parse(Data(contentsOf: sheetURL), sharedStrings: sharedStrings)
        guard let headerRow = allRows.first else { throw FileManagementError.noRows }
        let columnCount = max(headerRow.count, allRows.dropFirst().map(\.count).max() ?? 0)
        guard columnCount > 0 else { throw FileManagementError.noRows }
        var seen: [String: Int] = [:]
        let columns = (0..<columnCount).map { index -> XLSXColumn in
            let rawTitle = index < headerRow.count
                ? headerRow[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let base = rawTitle.isEmpty ? "第 \(index + 1) 列" : rawTitle
            seen[base, default: 0] += 1
            let count = seen[base] ?? 1
            return XLSXColumn(index: index, title: count == 1 ? base : "\(base) (\(count))")
        }
        return XLSXSheet(columns: columns, rows: Array(allRows.dropFirst()))
    }

    private static func firstWorksheetURL(in root: URL) throws -> URL {
        let workbookURL = root.appendingPathComponent("xl/workbook.xml")
        let relationshipsURL = root.appendingPathComponent("xl/_rels/workbook.xml.rels")
        if FileManager.default.fileExists(atPath: workbookURL.path),
           FileManager.default.fileExists(atPath: relationshipsURL.path),
           let relationshipID = try WorkbookParser.firstSheetRelationshipID(Data(contentsOf: workbookURL)),
           let target = try RelationshipsParser.target(
               for: relationshipID,
               data: Data(contentsOf: relationshipsURL)
           ) {
            let normalized = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/\(target)"
            let candidate = root.appendingPathComponent(normalized).standardizedFileURL
            guard candidate.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw FileManagementError.invalidWorkbook("工作表路径不安全")
            }
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let fallback = root.appendingPathComponent("xl/worksheets/sheet1.xml")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw FileManagementError.invalidWorkbook("找不到工作表")
        }
        return fallback
    }

    private static func createPackage(headers: [String], rows: [[String]], at root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("xl/_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("xl/worksheets", isDirectory: true),
            withIntermediateDirectories: true
        )
        let files: [(String, String)] = [
            ("[Content_Types].xml", contentTypesXML),
            ("_rels/.rels", packageRelationshipsXML),
            ("xl/workbook.xml", workbookXML),
            ("xl/_rels/workbook.xml.rels", workbookRelationshipsXML),
            ("xl/worksheets/sheet1.xml", worksheetXML(headers: headers, rows: rows))
        ]
        for (path, contents) in files {
            try Data(contents.utf8).write(to: root.appendingPathComponent(path), options: .atomic)
        }
    }

    private static func worksheetXML(headers: [String], rows: [[String]]) -> String {
        let values = [headers] + rows
        let xmlRows = values.enumerated().map { rowOffset, row in
            let cells = row.enumerated().map { columnOffset, value in
                let reference = "\(columnName(for: columnOffset))\(rowOffset + 1)"
                return "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(value))</t></is></c>"
            }.joined()
            return "<row r=\"\(rowOffset + 1)\">\(cells)</row>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(xmlRows)</sheetData></worksheet>
        """
    }

    private static func columnName(for zeroBasedIndex: Int) -> String {
        var number = zeroBasedIndex + 1
        var result = ""
        while number > 0 {
            number -= 1
            result = String(UnicodeScalar(65 + number % 26)!) + result
            number /= 26
        }
        return result
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
    """

    private static let packageRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="文件目录" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
    """
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var insideString = false
    private var insideText = false

    static func parse(_ data: Data) throws -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? FileManagementError.invalidWorkbook("共享字符串损坏") }
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { current = ""; insideString = true }
        if insideString, elementName == "t" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { insideText = false }
        if elementName == "si" { strings.append(current); insideString = false }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentColumn = 0
    private var currentType = ""
    private var currentValue = ""
    private var captureValue = false
    private var insideCell = false

    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    static func parse(_ data: Data, sharedStrings: [String]) throws -> [[String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? FileManagementError.invalidWorkbook("工作表损坏") }
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row": currentRow = []
        case "c":
            insideCell = true
            currentValue = ""
            currentType = attributeDict["t"] ?? ""
            currentColumn = Self.columnIndex(from: attributeDict["r"] ?? "A")
        case "v": captureValue = insideCell
        case "t": captureValue = insideCell && currentType == "inlineStr"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureValue { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v", "t": captureValue = false
        case "c":
            while currentRow.count <= currentColumn { currentRow.append("") }
            if currentType == "s", let index = Int(currentValue), sharedStrings.indices.contains(index) {
                currentRow[currentColumn] = sharedStrings[index]
            } else if currentType == "b" {
                currentRow[currentColumn] = currentValue == "1" ? "TRUE" : "FALSE"
            } else {
                currentRow[currentColumn] = currentValue
            }
            insideCell = false
        case "row": rows.append(currentRow)
        default: break
        }
    }

    private static func columnIndex(from reference: String) -> Int {
        reference.prefix { $0.isLetter }.reduce(0) { partial, character in
            partial * 26 + Int(character.asciiValue! - Character("A").asciiValue! + 1)
        } - 1
    }
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    private var relationshipID: String?

    static func firstSheetRelationshipID(_ data: Data) throws -> String? {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? FileManagementError.invalidWorkbook("工作簿损坏") }
        return delegate.relationshipID
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "sheet", relationshipID == nil {
            relationshipID = attributeDict["r:id"] ?? attributeDict["id"]
        }
    }
}

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private let requestedID: String
    private var matchedTarget: String?

    init(requestedID: String) { self.requestedID = requestedID }

    static func target(for id: String, data: Data) throws -> String? {
        let delegate = RelationshipsParser(requestedID: id)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? FileManagementError.invalidWorkbook("工作簿关系损坏") }
        return delegate.matchedTarget
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "Relationship", attributeDict["Id"] == requestedID {
            matchedTarget = attributeDict["Target"]
        }
    }
}
