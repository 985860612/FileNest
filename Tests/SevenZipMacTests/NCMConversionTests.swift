import CommonCrypto
import AVFoundation
import Foundation
import Testing
@testable import FileNestKit

@Suite("NCM conversion")
struct NCMConversionTests {
    @Test(
        "A real NCM sample becomes playable audio",
        .enabled(if: ProcessInfo.processInfo.environment["NCM_SAMPLE_PATH"] != nil)
    )
    func convertsRealSample() async throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["NCM_SAMPLE_PATH"]))
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try NCMConversionService.convert(
            source: source,
            destinationDirectory: root,
            cancellation: NCMCancellation(),
            progress: { _ in }
        )
        let size = try #require(output.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size > 1_000_000)
        let duration = try await AVURLAsset(url: output.url).load(.duration)
        #expect(duration.seconds > 1)
    }

    @Test("NCM audio is restored without re-encoding and MP3 metadata is added")
    func convertsMP3() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample.ncm")
        let audio = Data([0xff, 0xfb, 0x90, 0x64]) + Data(repeating: 0x5a, count: 8_192)
        try makeFixture(audio: audio, format: "mp3").write(to: source)

        var updates: [Double] = []
        let output = try NCMConversionService.convert(
            source: source,
            destinationDirectory: root,
            cancellation: NCMCancellation(),
            progress: { updates.append($0) }
        )

        #expect(output.url.pathExtension == "mp3")
        #expect(output.metadata.title == "测试歌曲")
        #expect(output.metadata.artist == "歌手甲/歌手乙")
        let result = try Data(contentsOf: output.url)
        #expect(result.starts(with: Data("ID3".utf8)))
        #expect(result.suffix(audio.count) == audio)
        #expect(updates.last == 1)
    }

    @Test("FLAC output keeps its stream marker and receives local metadata blocks")
    func convertsFLAC() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("lossless.ncm")
        var audio = Data("fLaC".utf8)
        audio.append(contentsOf: [0x80, 0x00, 0x00, 0x22])
        audio.append(Data(repeating: 0, count: 34))
        audio.append(Data(repeating: 0x33, count: 4_096))
        try makeFixture(audio: audio, format: "flac").write(to: source)

        let output = try NCMConversionService.convert(
            source: source,
            destinationDirectory: root,
            cancellation: NCMCancellation(),
            progress: { _ in }
        )
        let result = try Data(contentsOf: output.url)
        #expect(output.url.pathExtension == "flac")
        #expect(result.starts(with: Data("fLaC".utf8)))
        #expect(result[4] == 0x00)
        #expect(result.range(of: Data("TITLE=测试歌曲".utf8)) != nil)
        #expect(result.suffix(audio.count - 42) == audio.dropFirst(42))
    }

    @Test("Existing output is never overwritten")
    func avoidsExistingOutput() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample.ncm")
        let existing = root.appendingPathComponent("sample.mp3")
        try Data("existing".utf8).write(to: existing)
        try makeFixture(audio: Data([0xff, 0xfb, 0x01, 0x02]), format: "mp3").write(to: source)

        let output = try NCMConversionService.convert(
            source: source,
            destinationDirectory: root,
            cancellation: NCMCancellation(),
            progress: { _ in }
        )
        #expect(output.url.lastPathComponent == "sample 2.mp3")
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    @Test("Folder selection finds NCM files recursively and ignores hidden folders")
    func discoversFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("one.NCM"))
        try Data().write(to: nested.appendingPathComponent("two.ncm"))
        try Data().write(to: hidden.appendingPathComponent("secret.ncm"))
        try Data().write(to: root.appendingPathComponent("notes.txt"))

        let files = NCMWorkspaceModel.discoverNCMFiles(in: [root])
        #expect(files.map(\.lastPathComponent).sorted() == ["one.NCM", "two.ncm"])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filenest-ncm-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFixture(audio: Data, format: String) throws -> Data {
        let audioKey = Data("0123456789abcdef".utf8)
        let keyPrefix = Data("neteasecloudmusic".utf8)
        let coreKey = Data([0x68, 0x7a, 0x48, 0x52, 0x41, 0x6d, 0x73, 0x6f, 0x35, 0x6b, 0x49, 0x6e, 0x62, 0x61, 0x78, 0x57])
        let metadataKey = Data([0x23, 0x31, 0x34, 0x6c, 0x6a, 0x6b, 0x5f, 0x21, 0x5c, 0x5d, 0x26, 0x30, 0x55, 0x3c, 0x27, 0x28])

        let encryptedKey = try aesEncrypt(keyPrefix + audioKey, key: coreKey).map { $0 ^ 0x64 }
        let json: [String: Any] = [
            "musicName": "测试歌曲",
            "artist": [["歌手甲", 1], ["歌手乙", 2]],
            "album": "测试专辑",
            "format": format
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let encryptedMetadata = try aesEncrypt(Data("music:".utf8) + metadataJSON, key: metadataKey).base64EncodedData()
        let metadataPrefix = Data("163 key(Don't modify):".utf8)
        #expect(metadataPrefix.count == 22)
        let metadataBlock = (metadataPrefix + encryptedMetadata).map { $0 ^ 0x63 }
        let encryptedAudio = cryptAudio(audio, key: audioKey)

        var fixture = Data([0x43, 0x54, 0x45, 0x4e, 0x46, 0x44, 0x41, 0x4d, 0x00, 0x00])
        fixture.append(littleEndian(UInt32(encryptedKey.count)))
        fixture.append(contentsOf: encryptedKey)
        fixture.append(littleEndian(UInt32(metadataBlock.count)))
        fixture.append(contentsOf: metadataBlock)
        fixture.append(Data(repeating: 0, count: 5))
        fixture.append(littleEndian(0))
        fixture.append(littleEndian(0))
        fixture.append(encryptedAudio)
        return fixture
    }

    private func aesEncrypt(_ data: Data, key: Data) throws -> Data {
        let capacity = data.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        dataBuffer.baseAddress,
                        data.count,
                        outputBuffer.baseAddress,
                        capacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw NCMConversionError.damagedFile("测试加密失败") }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private func cryptAudio(_ data: Data, key: Data) -> Data {
        let key = [UInt8](key)
        var box = Array(0...255).map(UInt8.init)
        var last: UInt8 = 0
        var keyOffset = 0
        for index in 0..<256 {
            let value = box[index]
            let target = Int(value &+ last &+ key[keyOffset])
            box[index] = box[target]
            box[target] = value
            last = UInt8(target)
            keyOffset = (keyOffset + 1) % key.count
        }
        var bytes = [UInt8](data)
        for index in bytes.indices {
            let streamIndex = (index + 1) & 0xff
            let first = Int(box[streamIndex])
            let second = Int(box[(first + streamIndex) & 0xff])
            bytes[index] ^= box[(first + second) & 0xff]
        }
        return Data(bytes)
    }

    private func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
