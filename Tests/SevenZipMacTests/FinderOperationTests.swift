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
}
