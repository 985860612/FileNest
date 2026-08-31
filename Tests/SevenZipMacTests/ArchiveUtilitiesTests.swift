import Foundation
import Testing
@testable import FileNestKit

@Test func detectsReadableArchives() {
    #expect(ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/demo.7z")))
    #expect(ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/demo.RAR")))
    #expect(ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/cad_root.zip 2")))
    #expect(!ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/demo.txt")))
    #expect(!ArchiveUtilities.looksLikeArchive(URL(fileURLWithPath: "/tmp/notes.txt 2")))
}

@Test func derivesExtractionFolderFromNumberedArchiveCopy() {
    let archive = URL(fileURLWithPath: "/tmp/cad_root.zip 2")
    #expect(ArchiveUtilities.extractionFolder(for: archive).path == "/tmp/cad_root")
}

@Test func identifiesErrorsThatNeedAPasswordPrompt() {
    let required = ArchiveEngineError.operationFailed("Password required")
    let incorrect = ArchiveEngineError.operationFailed("Incorrect password or damaged archive")
    let damaged = ArchiveEngineError.operationFailed("Unsupported or damaged archive")

    #expect(WorkspaceModel.passwordPrompt(for: required)?.contains("受密码保护") == true)
    #expect(WorkspaceModel.passwordPrompt(for: incorrect)?.contains("密码不正确") == true)
    #expect(WorkspaceModel.passwordPrompt(for: damaged) == nil)
}

@Test(
    "Encrypted archives request a password and accept the correct one",
    .enabled(if: ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_INTEGRATION"] == "1")
)
func encryptedArchivePasswordRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("filenest-password-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let input = root.appendingPathComponent("secret.txt")
    let archive = root.appendingPathComponent("secret.7z")
    try Data("secret payload".utf8).write(to: input)
    try ArchiveEngine.shared.compress(
        inputs: [input],
        to: archive,
        format: .sevenZip,
        password: "correct-password",
        level: 6,
        dictionarySize: CompressionDictionarySize.mib16.rawValue,
        volumeSize: 0,
        cancellation: ArchiveCancellation(),
        progress: { _ in }
    )

    for (password, directory) in [("", "missing"), ("wrong-password", "wrong")] {
        do {
            try ArchiveEngine.shared.extract(
                archive: archive,
                to: root.appendingPathComponent(directory, isDirectory: true),
                password: password,
                cancellation: ArchiveCancellation(),
                progress: { _ in }
            )
            Issue.record("受保护的归档不应接受空密码或错误密码")
        } catch {
            #expect(WorkspaceModel.passwordPrompt(for: error) != nil)
        }
    }

    let output = root.appendingPathComponent("correct", isDirectory: true)
    try ArchiveEngine.shared.extract(
        archive: archive,
        to: output,
        password: "correct-password",
        cancellation: ArchiveCancellation(),
        progress: { _ in }
    )
    #expect(try Data(contentsOf: output.appendingPathComponent("secret.txt")) == Data("secret payload".utf8))
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
