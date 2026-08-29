import Foundation
import Testing
@testable import SevenZipMac

@Suite("Finder operations")
struct FinderOperationTests {
    @Test("Compression defaults to level six in every entry point")
    func defaultCompressionLevel() {
        #expect(CompressionDefaults.level == 6)
    }

    @Test("Finder actions expose dedicated window metadata")
    func actionMetadata() {
        #expect(FinderAction.compress(.sevenZip).title == "创建归档")
        #expect(FinderAction.extract.title == "解压归档")
        #expect(FinderAction.browse.title == "查看归档")
        #expect(FinderAction.browse.systemImage == "doc.text.magnifyingglass")
    }

    @Test("Extraction names handle compound and split archive extensions")
    func extractionNames() {
        #expect(FinderOperationModel.defaultExtractionName(
            for: URL(fileURLWithPath: "/tmp/photos.tar.gz")
        ) == "photos")
        #expect(FinderOperationModel.defaultExtractionName(
            for: URL(fileURLWithPath: "/tmp/backup.7z.001")
        ) == "backup")
    }

    @Test("Multiple archives receive separate folders under the selected destination")
    func multipleExtractionDestinations() {
        let root = URL(fileURLWithPath: "/tmp/Extracted", isDirectory: true)
        let archive = URL(fileURLWithPath: "/tmp/photos.zip")
        #expect(FinderOperationModel.extractionDestination(
            for: archive,
            selectedDestination: root,
            inputCount: 2
        ) == root.appendingPathComponent("photos", isDirectory: true))
        #expect(FinderOperationModel.extractionDestination(
            for: archive,
            selectedDestination: root,
            inputCount: 1
        ) == root)
    }

    @Test("Archive progress never moves backwards between callbacks")
    func archiveProgressIsMonotonic() {
        #expect(FinderOperationModel.monotonicProgress(current: nil, incoming: 0.2) == 0.2)
        #expect(FinderOperationModel.monotonicProgress(current: 0.7, incoming: 0) == 0.7)
        #expect(FinderOperationModel.monotonicProgress(current: 0.7, incoming: 0.9) == 0.9)
        #expect(FinderOperationModel.monotonicProgress(current: 0.7, incoming: nil) == 0.7)

        let compression = ArchiveEngine.scaledProgress(
            ArchiveProgress(completed: 50, total: 100, currentPath: "payload"),
            from: 0,
            to: 0.9
        )
        let splitting = ArchiveEngine.scaledProgress(
            ArchiveProgress(completed: 50, total: 100, currentPath: "payload.001"),
            from: 0.9,
            to: 1
        )
        #expect(compression.fraction == 0.45)
        #expect(splitting.fraction == 0.95)
    }

    @Test("Archive browser only exposes one directory level at a time")
    func archiveBrowserBuildsDirectoryLevels() {
        let entries = [
            ArchiveEntry(path: "project/README.md", size: 120, directory: false),
            ArchiveEntry(path: "project/Sources/main.swift", size: 240, directory: false),
            ArchiveEntry(path: "license.txt", size: 80, directory: false)
        ]

        let root = FinderOperationModel.browserItems(entries: entries, directory: "", searchText: "")
        #expect(root.map(\.name) == ["project", "license.txt"])
        #expect(root.first?.directory == true)

        let project = FinderOperationModel.browserItems(
            entries: entries,
            directory: "project",
            searchText: ""
        )
        #expect(project.map(\.name) == ["Sources", "README.md"])

        let search = FinderOperationModel.browserItems(
            entries: entries,
            directory: "project",
            searchText: "main"
        )
        #expect(search.map(\.path) == ["project/Sources/main.swift"])
    }
}
