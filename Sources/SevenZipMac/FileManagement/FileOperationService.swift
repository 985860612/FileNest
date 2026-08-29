import Foundation

enum FileOperationService {
    static func copyPreview(
        sheet: XLSXSheet,
        sourceColumn: XLSXColumn,
        destinationColumn: XLSXColumn,
        fileManager: FileManager = .default
    ) -> [FileOperationPreview] {
        sheet.rows.enumerated().compactMap { offset, row in
            let source = sheet.value(row: row, column: sourceColumn).trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = sheet.value(row: row, column: destinationColumn).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty || !destination.isEmpty else { return nil }
            let state: FileOperationState
            if source.isEmpty || destination.isEmpty {
                state = .invalid("路径为空")
            } else if !NSString(string: source).isAbsolutePath || !NSString(string: destination).isAbsolutePath {
                state = .invalid("必须使用绝对路径")
            } else if !fileManager.fileExists(atPath: source) {
                state = .missing
            } else {
                state = .ready
            }
            return FileOperationPreview(
                id: offset,
                sourcePath: source,
                destinationPath: destination,
                state: state
            )
        }
    }

    static func trashPreview(
        sheet: XLSXSheet,
        pathColumn: XLSXColumn,
        fileManager: FileManager = .default
    ) -> [FileOperationPreview] {
        sheet.rows.enumerated().compactMap { offset, row in
            let path = sheet.value(row: row, column: pathColumn).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            guard NSString(string: path).isAbsolutePath else {
                return FileOperationPreview(
                    id: offset,
                    sourcePath: path,
                    destinationPath: nil,
                    state: .invalid("必须使用绝对路径")
                )
            }
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let state: FileOperationState = !exists ? .missing : (isDirectory.boolValue ? .invalid("不是文件") : .ready)
            return FileOperationPreview(id: offset, sourcePath: path, destinationPath: nil, state: state)
        }
    }

    static func renamePreview(
        sheet: XLSXSheet,
        pathColumn: XLSXColumn,
        nameColumn: XLSXColumn,
        fileManager: FileManager = .default
    ) -> [FileOperationPreview] {
        var operations = sheet.rows.enumerated().compactMap { offset, row -> FileOperationPreview? in
            let source = sheet.value(row: row, column: pathColumn).trimmingCharacters(in: .whitespacesAndNewlines)
            let newName = sheet.value(row: row, column: nameColumn).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty || !newName.isEmpty else { return nil }

            let sourceURL = URL(fileURLWithPath: source)
            let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)
            let state: FileOperationState
            if source.isEmpty || newName.isEmpty {
                state = .invalid("路径或新文件名为空")
            } else if !NSString(string: source).isAbsolutePath {
                state = .invalid("必须使用绝对路径")
            } else if !isValidFileName(newName) {
                state = .invalid("新文件名无效")
            } else {
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: source, isDirectory: &isDirectory)
                if !exists {
                    state = .missing
                } else if isDirectory.boolValue {
                    state = .invalid("不是文件")
                } else if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
                    state = .invalid("名称未变化")
                } else if fileManager.fileExists(atPath: destinationURL.path) {
                    state = .invalid("目标已存在")
                } else {
                    state = .ready
                }
            }
            return FileOperationPreview(
                id: offset,
                sourcePath: source,
                destinationPath: destinationURL.path,
                state: state
            )
        }

        let executableIndices = operations.indices.filter { operations[$0].state.isExecutable }
        let sourceCounts = Dictionary(grouping: executableIndices, by: {
            normalizedPath(operations[$0].sourcePath)
        }).mapValues(\.count)
        let destinationCounts = Dictionary(grouping: executableIndices, by: {
            normalizedPath(operations[$0].destinationPath ?? "")
        }).mapValues(\.count)
        for index in operations.indices where operations[index].state.isExecutable {
            if sourceCounts[normalizedPath(operations[index].sourcePath), default: 0] > 1 {
                operations[index].state = .invalid("源文件重复")
            } else if destinationCounts[normalizedPath(operations[index].destinationPath ?? ""), default: 0] > 1 {
                operations[index].state = .invalid("目标名称重复")
            }
        }
        return operations
    }

    static func executeCopies(
        _ operations: [FileOperationPreview],
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ path: String) -> Void = { _, _, _ in }
    ) -> ([FileOperationPreview], FileOperationSummary) {
        var results = operations
        var succeeded = 0
        for index in results.indices {
            defer { progress(index + 1, results.count, results[index].sourcePath) }
            guard results[index].state.isExecutable,
                  let destination = results[index].destinationPath else { continue }
            do {
                let destinationURL = URL(fileURLWithPath: destination)
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destination) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try fileManager.copyItem(atPath: results[index].sourcePath, toPath: destination)
                results[index].state = .success
                succeeded += 1
            } catch {
                results[index].state = .failed(error.localizedDescription)
            }
        }
        return (results, FileOperationSummary(total: results.count, succeeded: succeeded))
    }

    static func executeTrash(
        _ operations: [FileOperationPreview],
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ path: String) -> Void = { _, _, _ in }
    ) -> ([FileOperationPreview], FileOperationSummary) {
        var results = operations
        var succeeded = 0
        for index in results.indices {
            defer { progress(index + 1, results.count, results[index].sourcePath) }
            guard results[index].state.isExecutable else { continue }
            do {
                try fileManager.trashItem(
                    at: URL(fileURLWithPath: results[index].sourcePath),
                    resultingItemURL: nil
                )
                results[index].state = .success
                succeeded += 1
            } catch {
                results[index].state = .failed(error.localizedDescription)
            }
        }
        return (results, FileOperationSummary(total: results.count, succeeded: succeeded))
    }

    static func executeRenames(
        _ operations: [FileOperationPreview],
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ path: String) -> Void = { _, _, _ in }
    ) -> ([FileOperationPreview], FileOperationSummary) {
        var results = operations
        var succeeded = 0
        for index in results.indices {
            defer { progress(index + 1, results.count, results[index].sourcePath) }
            guard results[index].state.isExecutable,
                  let destination = results[index].destinationPath else { continue }
            do {
                if fileManager.fileExists(atPath: destination) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try fileManager.moveItem(atPath: results[index].sourcePath, toPath: destination)
                results[index].state = .success
                succeeded += 1
            } catch {
                results[index].state = .failed(error.localizedDescription)
            }
        }
        return (results, FileOperationSummary(total: results.count, succeeded: succeeded))
    }

    private static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && name != "." && name != ".." &&
            name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\n\r\0")) == nil
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
