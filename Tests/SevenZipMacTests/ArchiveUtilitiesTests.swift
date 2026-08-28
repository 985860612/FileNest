import Foundation
import Testing
@testable import SevenZipMac

@Test func detectsReadableArchives() {
    #expect(ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/demo.7z")))
    #expect(ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/demo.RAR")))
    #expect(!ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/demo.txt")))
}

@Test func derivesExtractionFolder() {
    let url = URL(fileURLWithPath: "/tmp/backup.tar.gz")
    #expect(ArchiveUtilities.extractionFolder(for: url).lastPathComponent == "backup")
}

@Test func createsArchiveNameFromSingleInput() {
    let input = URL(fileURLWithPath: "/tmp/Project")
    let output = ArchiveUtilities.archiveDestination(for: [input], format: .sevenZip)
    #expect(output.lastPathComponent == "Project.7z")
}

@Test func derivesExtractionFolderFromFirstVolume() {
    let archive = URL(fileURLWithPath: "/tmp/backup.7z.001")
    #expect(ArchiveUtilities.extractionFolder(for: archive).path == "/tmp/backup")
    #expect(ArchiveUtilities.looksLikeArchive(archive))
    #expect(!ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/backup.7z.002")))
}
