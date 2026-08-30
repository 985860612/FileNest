import Foundation

enum SpreadsheetToolError: LocalizedError {
    case groupingColumnMissing

    var errorDescription: String? {
        switch self {
        case .groupingColumnMissing: "请选择分组列。"
        }
    }
}

enum SpreadsheetToolService {
    static func groupedRows(sheet: XLSXSheet, groupingColumn: XLSXColumn) throws -> [[String]] {
        guard sheet.columns.contains(groupingColumn) else { throw SpreadsheetToolError.groupingColumnMissing }
        var order: [String] = []
        var groups: [String: [[String]]] = [:]
        for row in sheet.rows {
            let key = sheet.value(row: row, column: groupingColumn)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.map { key in
            let rows = groups[key] ?? []
            return sheet.columns.map { column in
                if column == groupingColumn { return key }
                var seen = Set<String>()
                return rows.compactMap { row -> String? in
                    let value = sheet.value(row: row, column: column).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, seen.insert(value).inserted else { return nil }
                    return value
                }.joined(separator: ",")
            }
        }
    }
}
