import Foundation
import Testing
@testable import FileNestKit

@Suite("CLI and MCP automation interface")
struct AutomationInterfaceTests {
    @Test("Every synchronous tool has a unique stable name")
    func toolInventory() {
        #expect(FileNestAutomation.toolNames.count == 19)
        #expect(Set(FileNestAutomation.toolNames).count == FileNestAutomation.toolNames.count)
        #expect(FileNestAutomation.toolNames.contains("archive_create"))
        #expect(FileNestAutomation.toolNames.contains("image_process"))
        #expect(FileNestAutomation.toolNames.contains("pdf_signatures"))
    }

    @Test("Hash facade returns the known digest as JSON-compatible data")
    func hashFacade() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNestAutomation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("hello".utf8).write(to: file)

        let result = try FileNestAutomation.call("hash_compute", arguments: [
            "files": [file.path],
            "algorithm": "SHA-256",
        ])
        let files = try #require(result["files"] as? [[String: Any]])
        #expect(files.count == 1)
        #expect(files[0]["digest"] as? String == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(JSONSerialization.isValidJSONObject(result))
    }

    @Test("Mutating tools reject calls without explicit confirmation", arguments: [
        "files_rename", "files_trash", "file_extension_repair", "file_sanitize_names",
    ])
    func confirmationGuard(tool: String) {
        #expect(throws: FileNestAutomationError.self) {
            try FileNestAutomation.call(tool, arguments: [:])
        }
    }

    @Test("Replacing original images also requires confirmation")
    func imageConfirmationGuard() {
        #expect(throws: FileNestAutomationError.self) {
            try FileNestAutomation.call("image_process", arguments: [
                "root": "/tmp",
                "replaceOriginals": true,
                "format": "webp",
            ])
        }
    }

    @Test("Image format aliases accepted by automation match the app options", arguments: [
        "keep", "jpeg", "jpg", "png", "heic", "webp",
    ])
    func imageFormats(format: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNestImages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try FileNestAutomation.call("image_process", arguments: [
            "root": root.path,
            "format": format,
        ])
        #expect(result["total"] as? Int == 0)
    }

    @Test("Archive facade creates, lists and extracts without a subprocess", .enabled(if: ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_INTEGRATION"] == "1"))
    func archiveRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNestArchiveAutomation-\(UUID().uuidString)", isDirectory: true)
        let input = root.appendingPathComponent("input.txt")
        let archive = root.appendingPathComponent("sample.7z")
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("automation round trip".utf8).write(to: input)

        _ = try FileNestAutomation.call("archive_create", arguments: [
            "inputs": [input.path], "output": archive.path, "format": "7z",
        ])
        let listing = try FileNestAutomation.call("archive_list", arguments: ["archive": archive.path])
        let entries = try #require(listing["entries"] as? [[String: Any]])
        #expect(entries.contains { $0["path"] as? String == "input.txt" })
        _ = try FileNestAutomation.call("archive_extract", arguments: ["archive": archive.path, "output": output.path])
        #expect(try String(contentsOf: output.appendingPathComponent("input.txt"), encoding: .utf8) == "automation round trip")
    }
}
