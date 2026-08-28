import Foundation
import Testing
@testable import SevenZipMac

@Suite("Hash tool")
struct HashToolTests {
    @Test("Known digests are calculated without command line tools")
    func knownDigests() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("SevenZipMacHash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("hello".utf8).write(to: file)

        #expect(try FileHashService.digest(file: file, algorithm: .md5) == "5d41402abc4b2a76b9719d911017c592")
        #expect(try FileHashService.digest(file: file, algorithm: .sha1) == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        #expect(try FileHashService.digest(file: file, algorithm: .sha256) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(try FileHashService.digest(file: file, algorithm: .sha512) == "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043")
    }

    @Test("Expected hash can be extracted from common checksum text")
    @MainActor
    func expectedHashVerification() {
        let model = HashWorkspaceModel()
        model.algorithm = .sha256
        model.expectedHash = "SHA256 (sample.zip) = 2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"
        let result = FileHashResult(
            url: URL(fileURLWithPath: "/tmp/sample.zip"),
            digest: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            errorMessage: nil
        )
        #expect(model.verificationState(for: result) == .matched)
        model.expectedHash = String(repeating: "0", count: 64)
        #expect(model.verificationState(for: result) == .mismatched)
    }
}
