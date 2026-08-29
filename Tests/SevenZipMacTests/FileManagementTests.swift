import Foundation
import Testing
@testable import SevenZipMac

@Suite("File management")
struct FileManagementTests {
    @Test("Changing workbook columns refreshes the preview automatically")
    @MainActor
    func workbookColumnsRefreshPreview() {
        let source = XLSXColumn(index: 0, title: "源文件")
        let destination = XLSXColumn(index: 1, title: "目标文件")
        let sheet = XLSXSheet(
            columns: [source, destination],
            rows: [["/tmp/missing-source.txt", "/tmp/output.txt"]]
        )
        let model = FileManagementWorkspaceModel()
        model.mode = .copy
        model.sheet = sheet

        model.sourceColumn = source
        #expect(model.operations.isEmpty)

        model.destinationColumn = destination
        #expect(model.operations.count == 1)
        #expect(model.statusMessage == "预览完成，共 1 项")
    }

    @Test("Directory scanning can include or exclude descendants")
    func directoryScanning() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("top".utf8).write(to: root.appendingPathComponent("top.txt"))
        try Data("nested".utf8).write(to: nested.appendingPathComponent("child.pdf"))

        let shallow = try FileCatalogService.scan(directory: root, recursively: false)
        let recursive = try FileCatalogService.scan(directory: root, recursively: true)

        #expect(shallow.map(\.fileName) == ["top"])
        #expect(recursive.map(\.fileName) == ["child", "top"])
        #expect(recursive.first?.fileExtension == "pdf")
    }

    @Test("Desktop export names avoid replacing an existing workbook")
    func desktopExportNamesAvoidCollisions() throws {
        let desktop = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: desktop) }
        let directory = URL(fileURLWithPath: "/tmp/项目资料", isDirectory: true)
        let date = Date(timeIntervalSince1970: 0)
        let first = FileCatalogService.desktopExportURL(
            for: directory,
            desktop: desktop,
            date: date
        )
        #expect(first.lastPathComponent.hasPrefix("文件目录_项目资料_"))
        #expect(first.pathExtension == "xlsx")

        try Data().write(to: first)
        let second = FileCatalogService.desktopExportURL(
            for: directory,
            desktop: desktop,
            date: date
        )
        #expect(second.deletingPathExtension().lastPathComponent ==
            first.deletingPathExtension().lastPathComponent + "_2")
    }

    @Test("Copy preview validates paths and execution preserves the source")
    func copyPreviewAndExecution() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("out/copied.txt")
        try Data("hello".utf8).write(to: source)
        let sheet = XLSXSheet(
            columns: [XLSXColumn(index: 0, title: "源"), XLSXColumn(index: 1, title: "目标")],
            rows: [
                [source.path, destination.path],
                [root.appendingPathComponent("missing").path, destination.path],
                ["relative.txt", "out.txt"]
            ]
        )

        let preview = FileOperationService.copyPreview(
            sheet: sheet,
            sourceColumn: sheet.columns[0],
            destinationColumn: sheet.columns[1]
        )
        #expect(preview[0].state == .ready)
        #expect(preview[1].state == .missing)
        #expect(preview[2].state == .invalid("必须使用绝对路径"))

        let (results, summary) = FileOperationService.executeCopies(preview)
        #expect(results[0].state == .success)
        #expect(summary.succeeded == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(String(data: try Data(contentsOf: destination), encoding: .utf8) == "hello")
    }

    @Test("Rename preview validates names and execution moves files in place")
    func renamePreviewAndExecution() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("before.txt")
        let collisionSource = root.appendingPathComponent("collision-source.txt")
        let duplicateSourceA = root.appendingPathComponent("duplicate-a.txt")
        let duplicateSourceB = root.appendingPathComponent("duplicate-b.txt")
        let existing = root.appendingPathComponent("existing.txt")
        for file in [source, collisionSource, duplicateSourceA, duplicateSourceB, existing] {
            try Data(file.lastPathComponent.utf8).write(to: file)
        }
        let sheet = XLSXSheet(
            columns: [XLSXColumn(index: 0, title: "文件路径"), XLSXColumn(index: 1, title: "新文件名")],
            rows: [
                [source.path, "after.txt"],
                [collisionSource.path, "existing.txt"],
                [duplicateSourceA.path, "same.txt"],
                [duplicateSourceB.path, "same.txt"],
                [root.appendingPathComponent("missing.txt").path, "missing-new.txt"],
                [source.path, "nested/name.txt"]
            ]
        )

        let preview = FileOperationService.renamePreview(
            sheet: sheet,
            pathColumn: sheet.columns[0],
            nameColumn: sheet.columns[1]
        )
        #expect(preview[0].state == .ready)
        #expect(preview[1].state == .invalid("目标已存在"))
        #expect(preview[2].state == .invalid("目标名称重复"))
        #expect(preview[3].state == .invalid("目标名称重复"))
        #expect(preview[4].state == .missing)
        #expect(preview[5].state == .invalid("新文件名无效"))

        let (results, summary) = FileOperationService.executeRenames(preview)
        let renamed = root.appendingPathComponent("after.txt")
        #expect(results[0].state == .success)
        #expect(summary.succeeded == 1)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test("Extracted XLSX supports shared strings, inline strings and duplicate headers")
    func readsExtractedWorkbook() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let worksheets = root.appendingPathComponent("xl/worksheets", isDirectory: true)
        let relationships = root.appendingPathComponent("xl/_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: worksheets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relationships, withIntermediateDirectories: true)
        try write("""
        <?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId9"/></sheets></workbook>
        """, to: root.appendingPathComponent("xl/workbook.xml"))
        try write("""
        <?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId9" Target="worksheets/sheet1.xml"/></Relationships>
        """, to: relationships.appendingPathComponent("workbook.xml.rels"))
        try write("""
        <?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>路径</t></si><si><t>状态</t></si><si><t>/tmp/a.txt</t></si></sst>
        """, to: root.appendingPathComponent("xl/sharedStrings.xml"))
        try write("""
        <?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2" t="inlineStr"><is><t>就绪</t></is></c></row></sheetData></worksheet>
        """, to: worksheets.appendingPathComponent("sheet1.xml"))

        let sheet = try XLSXDocument.readExtractedWorkbook(at: root)
        #expect(sheet.columns.map(\.title) == ["路径", "路径 (2)", "状态"])
        #expect(sheet.rows == [["/tmp/a.txt", "", "就绪"]])
    }

    @Test("7-Zip SDK writes and reads a real XLSX", .enabled(if: ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_INTEGRATION"] == "1"))
    func xlsxRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workbook = root.appendingPathComponent("catalog.xlsx")
        try XLSXDocument.write(
            headers: ["完整路径", "备注"],
            rows: [["/tmp/测试 & sample.txt", "含空格 <ok>"]],
            to: workbook
        )
        var sheet = try XLSXDocument.read(from: workbook)
        #expect(sheet.columns.map(\.title) == ["完整路径", "备注"])
        #expect(sheet.rows == [["/tmp/测试 & sample.txt", "含空格 <ok>"]])

        try XLSXDocument.write(
            headers: ["路径", "状态"],
            rows: [["/tmp/replaced.txt", "已覆盖"]],
            to: workbook
        )
        sheet = try XLSXDocument.read(from: workbook)
        #expect(sheet.columns.map(\.title) == ["路径", "状态"])
        #expect(sheet.rows == [["/tmp/replaced.txt", "已覆盖"]])
    }

    @Test("7-Zip SDK dictionary and volume archive round trip", .enabled(if: ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_INTEGRATION"] == "1"))
    func sdkVolumeRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("payload.bin")
        var state: UInt64 = 0x1234_5678_9abc_def0
        let payload = Data((0..<(512 * 1024)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return UInt8(truncatingIfNeeded: state >> 24)
        })
        try payload.write(to: input)
        for format in ArchiveFormat.allCases {
            let archive = root.appendingPathComponent("payload.\(format.fileExtension)")
            try ArchiveEngine.shared.compress(
                inputs: [input],
                to: archive,
                format: format,
                password: "",
                level: 5,
                dictionarySize: format == .sevenZip ? CompressionDictionarySize.mib16.rawValue : 0,
                volumeSize: 64 * 1024,
                cancellation: ArchiveCancellation(),
                progress: { _ in }
            )
            let first = root.appendingPathComponent("payload.\(format.fileExtension).001")
            #expect(try ArchiveVolumeUtilities.volumeURLs(startingAt: first).count > 1)

            let output = root.appendingPathComponent("output-\(format.fileExtension)", isDirectory: true)
            try ArchiveEngine.shared.extract(
                archive: first,
                to: output,
                password: "",
                cancellation: ArchiveCancellation(),
                progress: { _ in }
            )
            #expect(try Data(contentsOf: output.appendingPathComponent("payload.bin")) == payload)
        }
    }

    @Test("Compression excludes macOS metadata but keeps normal dotfiles", .enabled(if: ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_INTEGRATION"] == "1"))
    func excludesMacOSMetadata() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("payload".utf8).write(to: root.appendingPathComponent("payload.txt"))
        try Data("rules".utf8).write(to: root.appendingPathComponent(".gitignore"))
        try Data("metadata".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        let metadataDirectory = root.appendingPathComponent("__MACOSX", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try Data("sidecar".utf8).write(to: metadataDirectory.appendingPathComponent("._payload.txt"))

        let archive = root.deletingLastPathComponent().appendingPathComponent("filtered-\(UUID().uuidString).7z")
        defer { try? FileManager.default.removeItem(at: archive) }
        try ArchiveEngine.shared.compress(
            inputs: [root],
            to: archive,
            format: .sevenZip,
            password: "",
            level: 5,
            dictionarySize: CompressionDictionarySize.mib16.rawValue,
            excludeMacOSMetadata: true,
            volumeSize: 0,
            cancellation: ArchiveCancellation(),
            progress: { _ in }
        )

        let paths = try ArchiveEngine.shared.list(archive: archive).map(\.path)
        #expect(paths.contains { $0.hasSuffix("/payload.txt") })
        #expect(paths.contains { $0.hasSuffix("/.gitignore") })
        #expect(!paths.contains { $0.contains(".DS_Store") })
        #expect(!paths.contains { $0.contains("__MACOSX") })
        #expect(!paths.contains { $0.contains("._payload.txt") })
    }

    @Test("Archive volumes split and rejoin without changing bytes")
    func volumeRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("sample.7z")
        let original = Data((0..<97).map { UInt8($0) })
        try original.write(to: archive)

        try ArchiveVolumeUtilities.split(
            archive: archive,
            volumeSize: 16,
            cancellation: ArchiveCancellation(),
            progress: { _ in }
        )
        let first = root.appendingPathComponent("sample.7z.001")
        let volumes = try ArchiveVolumeUtilities.volumeURLs(startingAt: first)
        #expect(volumes.count == 7)
        #expect(!FileManager.default.fileExists(atPath: archive.path))

        let prepared = try ArchiveVolumeUtilities.prepareForReading(
            first,
            cancellation: ArchiveCancellation(),
            progress: { _ in }
        )
        defer { prepared.cleanUp() }
        #expect(try Data(contentsOf: prepared.url) == original)
    }

    @Test("A missing middle archive volume is rejected")
    func missingVolume() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("sample.zip")
        try Data(repeating: 7, count: 40).write(to: archive)
        try ArchiveVolumeUtilities.split(
            archive: archive,
            volumeSize: 10,
            cancellation: ArchiveCancellation(),
            progress: { _ in }
        )
        try FileManager.default.removeItem(at: root.appendingPathComponent("sample.zip.002"))

        #expect(throws: ArchiveEngineError.self) {
            try ArchiveVolumeUtilities.volumeURLs(
                startingAt: root.appendingPathComponent("sample.zip.001")
            )
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SevenZipMacTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }
}
