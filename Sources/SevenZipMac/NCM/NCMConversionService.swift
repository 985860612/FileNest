import CommonCrypto
import Foundation

struct NCMAudioMetadata: Equatable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let declaredFormat: String?
}

struct NCMConversionOutput: Sendable {
    let url: URL
    let metadata: NCMAudioMetadata
}

enum NCMConversionError: LocalizedError, Equatable {
    case invalidFile
    case damagedFile(String)
    case unsupportedAudioFormat
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidFile: "不是有效的 NCM 文件"
        case .damagedFile(let reason): "NCM 文件已损坏：\(reason)"
        case .unsupportedAudioFormat: "无法识别 NCM 中的音频格式"
        case .cancelled: "已取消"
        }
    }
}

final class NCMCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

enum NCMConversionService {
    private static let magic = Data([0x43, 0x54, 0x45, 0x4e, 0x46, 0x44, 0x41, 0x4d])
    private static let coreKey = Data([0x68, 0x7a, 0x48, 0x52, 0x41, 0x6d, 0x73, 0x6f, 0x35, 0x6b, 0x49, 0x6e, 0x62, 0x61, 0x78, 0x57])
    private static let metadataKey = Data([0x23, 0x31, 0x34, 0x6c, 0x6a, 0x6b, 0x5f, 0x21, 0x5c, 0x5d, 0x26, 0x30, 0x55, 0x3c, 0x27, 0x28])
    private static let keyPrefixLength = 17
    private static let metadataPrefixLength = 22
    private static let chunkSize = 1_048_576

    static func convert(
        source: URL,
        destinationDirectory: URL,
        cancellation: NCMCancellation,
        progress: @escaping (Double) -> Void
    ) throws -> NCMConversionOutput {
        let parsed = try parseHeader(source: source)
        guard !cancellation.isCancelled else { throw NCMConversionError.cancelled }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { try? sourceHandle.close() }
        try sourceHandle.seek(toOffset: parsed.audioOffset)

        let firstEncrypted = try sourceHandle.read(upToCount: chunkSize) ?? Data()
        guard !firstEncrypted.isEmpty else { throw NCMConversionError.damagedFile("缺少音频数据") }
        var streamOffset = 0
        let firstAudio = decryptAudio(firstEncrypted, keyBox: parsed.keyBox, offset: &streamOffset)
        let format = try audioFormat(firstAudio, declared: parsed.metadata.declaredFormat)
        let destination = uniqueDestination(
            directory: destinationDirectory,
            stem: source.deletingPathExtension().lastPathComponent,
            extension: format.fileExtension
        )
        let temporary = destinationDirectory.appendingPathComponent(".filenest-\(UUID().uuidString).partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: temporary)
        var completed = UInt64(0)
        let audioLength = parsed.fileSize - parsed.audioOffset

        do {
            defer { try? outputHandle.close() }
            let decoratedFirstAudio = decorateFirstAudio(
                format: format,
                firstAudio: firstAudio,
                metadata: parsed.metadata,
                cover: parsed.cover
            )
            try outputHandle.write(contentsOf: decoratedFirstAudio)
            completed += UInt64(firstEncrypted.count)
            progress(min(1, Double(completed) / Double(audioLength)))

            while true {
                guard !cancellation.isCancelled else { throw NCMConversionError.cancelled }
                let encrypted = try sourceHandle.read(upToCount: chunkSize) ?? Data()
                if encrypted.isEmpty { break }
                let decrypted = decryptAudio(encrypted, keyBox: parsed.keyBox, offset: &streamOffset)
                try outputHandle.write(contentsOf: decrypted)
                completed += UInt64(encrypted.count)
                progress(min(1, Double(completed) / Double(audioLength)))
            }
            try outputHandle.synchronize()
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        progress(1)
        return NCMConversionOutput(url: destination, metadata: parsed.metadata)
    }

    private static func parseHeader(source: URL) throws -> ParsedNCM {
        let fileSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init) ?? 0
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        guard try readExact(handle, count: magic.count) == magic else { throw NCMConversionError.invalidFile }
        _ = try readExact(handle, count: 2)

        let encryptedKey = try readSizedBlock(handle, maximum: 1_048_576, label: "密钥")
        let rawKey = Data(encryptedKey.map { $0 ^ 0x64 })
        let decryptedKey = try aesDecrypt(rawKey, key: coreKey)
        guard decryptedKey.count > keyPrefixLength else { throw NCMConversionError.damagedFile("密钥无效") }
        let audioKey = Data(decryptedKey.dropFirst(keyPrefixLength))
        guard !audioKey.isEmpty else { throw NCMConversionError.damagedFile("音频密钥为空") }
        let keyBox = buildKeyBox(audioKey)

        let encryptedMetadata = try readSizedBlock(handle, maximum: 16 * 1_048_576, label: "元数据", allowsEmpty: true)
        let metadata = try decodeMetadata(encryptedMetadata)
        _ = try readExact(handle, count: 5)

        let coverFrameLength = Int(try readUInt32(handle))
        let coverLength = Int(try readUInt32(handle))
        guard coverFrameLength >= coverLength, coverFrameLength <= 64 * 1_048_576 else {
            throw NCMConversionError.damagedFile("封面长度无效")
        }
        let cover = try readExact(handle, count: coverLength)
        if coverFrameLength > coverLength {
            _ = try readExact(handle, count: coverFrameLength - coverLength)
        }
        let audioOffset = try handle.offset()
        guard audioOffset < fileSize else { throw NCMConversionError.damagedFile("缺少音频数据") }
        return ParsedNCM(
            keyBox: keyBox,
            metadata: metadata,
            cover: cover,
            audioOffset: audioOffset,
            fileSize: fileSize
        )
    }

    private static func decodeMetadata(_ encrypted: Data) throws -> NCMAudioMetadata {
        guard !encrypted.isEmpty else {
            return NCMAudioMetadata(title: nil, artist: nil, album: nil, declaredFormat: nil)
        }
        let xorData = Data(encrypted.map { $0 ^ 0x63 })
        guard xorData.count > metadataPrefixLength,
              let decoded = Data(base64Encoded: xorData.dropFirst(metadataPrefixLength)) else {
            throw NCMConversionError.damagedFile("元数据编码无效")
        }
        let clear = try aesDecrypt(decoded, key: metadataKey)
        guard clear.count > 6 else { throw NCMConversionError.damagedFile("元数据为空") }
        let jsonData = Data(clear.dropFirst(6))
        guard let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NCMConversionError.damagedFile("元数据 JSON 无效")
        }
        let artists = (object["artist"] as? [[Any]])?
            .compactMap { $0.first as? String }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return NCMAudioMetadata(
            title: object["musicName"] as? String,
            artist: artists?.isEmpty == false ? artists : nil,
            album: object["album"] as? String,
            declaredFormat: (object["format"] as? String)?.lowercased()
        )
    }

    private static func readSizedBlock(
        _ handle: FileHandle,
        maximum: Int,
        label: String,
        allowsEmpty: Bool = false
    ) throws -> Data {
        let count = Int(try readUInt32(handle))
        guard count <= maximum, allowsEmpty || count > 0 else {
            throw NCMConversionError.damagedFile("\(label)长度无效")
        }
        return try readExact(handle, count: count)
    }

    private static func readUInt32(_ handle: FileHandle) throws -> UInt32 {
        let data = try readExact(handle, count: 4)
        return data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    private static func readExact(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0 else { throw NCMConversionError.damagedFile("数据长度无效") }
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw NCMConversionError.damagedFile("文件提前结束") }
        return data
    }

    private static func aesDecrypt(_ data: Data, key: Data) throws -> Data {
        guard !data.isEmpty, data.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw NCMConversionError.damagedFile("AES 数据长度无效")
        }
        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        dataBuffer.baseAddress,
                        data.count,
                        outputBuffer.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw NCMConversionError.damagedFile("AES 解密失败") }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func buildKeyBox(_ key: Data) -> [UInt8] {
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
        return box
    }

    private static func decryptAudio(_ data: Data, keyBox: [UInt8], offset: inout Int) -> Data {
        var bytes = [UInt8](data)
        for index in bytes.indices {
            let streamIndex = (offset + index + 1) & 0xff
            let first = Int(keyBox[streamIndex])
            let second = Int(keyBox[(first + streamIndex) & 0xff])
            bytes[index] ^= keyBox[(first + second) & 0xff]
        }
        offset += bytes.count
        return Data(bytes)
    }

    private static func audioFormat(_ data: Data, declared: String?) throws -> AudioFormat {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x66, 0x4c, 0x61, 0x43]) { return .flac }
        if bytes.starts(with: [0x49, 0x44, 0x33]) { return .mp3 }
        if bytes.count >= 2, bytes[0] == 0xff, bytes[1] & 0xe0 == 0xe0 { return .mp3 }
        if declared == "flac" { return .flac }
        if declared == "mp3" { return .mp3 }
        throw NCMConversionError.unsupportedAudioFormat
    }

    private static func uniqueDestination(directory: URL, stem: String, extension fileExtension: String) -> URL {
        let initial = directory.appendingPathComponent(stem).appendingPathExtension(fileExtension)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }
        for index in 2...9_999 {
            let candidate = directory.appendingPathComponent("\(stem) \(index)").appendingPathExtension(fileExtension)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString)").appendingPathExtension(fileExtension)
    }

    private static func decorateFirstAudio(
        format: AudioFormat,
        firstAudio: Data,
        metadata: NCMAudioMetadata,
        cover: Data
    ) -> Data {
        switch format {
        case .mp3:
            guard !firstAudio.starts(with: [0x49, 0x44, 0x33]) else { return firstAudio }
            let tag = id3Tag(metadata: metadata, cover: cover)
            return tag + firstAudio
        case .flac:
            guard firstAudio.starts(with: [0x66, 0x4c, 0x61, 0x43]) else { return firstAudio }
            guard firstAudio.count >= 8 else { return firstAudio }
            let header = [UInt8](firstAudio[4..<8])
            guard header[0] & 0x7f == 0 else { return firstAudio }
            let streamInfoLength = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
            let streamInfoEnd = 8 + streamInfoLength
            guard streamInfoEnd <= firstAudio.count else { return firstAudio }
            let streamInfoWasLast = header[0] & 0x80 != 0
            var streamInfo = Data(firstAudio[4..<streamInfoEnd])
            streamInfo[streamInfo.startIndex] &= 0x7f

            var payloads: [(UInt8, Data)] = []
            let comments = vorbisCommentBlock(metadata)
            if !comments.isEmpty { payloads.append((4, comments)) }
            if !cover.isEmpty { payloads.append((6, flacPicture(cover))) }
            guard !payloads.isEmpty else { return firstAudio }

            var decorated = Data(firstAudio.prefix(4))
            decorated.append(streamInfo)
            for (index, item) in payloads.enumerated() {
                decorated.append(flacBlock(
                    type: item.0,
                    payload: item.1,
                    isLast: streamInfoWasLast && index == payloads.count - 1
                ))
            }
            decorated.append(firstAudio.dropFirst(streamInfoEnd))
            return decorated
        }
    }

    private static func id3Tag(metadata: NCMAudioMetadata, cover: Data) -> Data {
        var frames = Data()
        if let title = metadata.title, !title.isEmpty { frames.append(id3TextFrame("TIT2", value: title)) }
        if let artist = metadata.artist, !artist.isEmpty { frames.append(id3TextFrame("TPE1", value: artist)) }
        if let album = metadata.album, !album.isEmpty { frames.append(id3TextFrame("TALB", value: album)) }
        if !cover.isEmpty {
            let mime = cover.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "image/png" : "image/jpeg"
            var payload = Data([0x03])
            payload.append(Data(mime.utf8))
            payload.append(0)
            payload.append(0x03)
            payload.append(0)
            payload.append(cover)
            frames.append(id3Frame("APIC", payload: payload))
        }
        guard !frames.isEmpty else { return Data() }
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [0x04, 0x00, 0x00])
        tag.append(contentsOf: synchsafe(frames.count))
        tag.append(frames)
        return tag
    }

    private static func id3TextFrame(_ name: String, value: String) -> Data {
        var payload = Data([0x03])
        payload.append(Data(value.utf8))
        return id3Frame(name, payload: payload)
    }

    private static func id3Frame(_ name: String, payload: Data) -> Data {
        var frame = Data(name.utf8)
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian, Array.init))
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(payload)
        return frame
    }

    private static func synchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7f), UInt8((value >> 14) & 0x7f), UInt8((value >> 7) & 0x7f), UInt8(value & 0x7f)]
    }

    private static func vorbisCommentBlock(_ metadata: NCMAudioMetadata) -> Data {
        let comments = [
            metadata.title.map { "TITLE=\($0)" },
            metadata.artist.map { "ARTIST=\($0)" },
            metadata.album.map { "ALBUM=\($0)" }
        ].compactMap { $0 }.filter { !$0.hasSuffix("=") }
        guard !comments.isEmpty else { return Data() }
        let vendor = Data("FileNest".utf8)
        var payload = littleEndian(UInt32(vendor.count))
        payload.append(vendor)
        payload.append(littleEndian(UInt32(comments.count)))
        for comment in comments {
            let data = Data(comment.utf8)
            payload.append(littleEndian(UInt32(data.count)))
            payload.append(data)
        }
        return payload
    }

    private static func flacPicture(_ cover: Data) -> Data {
        let mime = Data((cover.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "image/png" : "image/jpeg").utf8)
        var payload = bigEndian(3)
        payload.append(bigEndian(UInt32(mime.count)))
        payload.append(mime)
        payload.append(bigEndian(0))
        payload.append(bigEndian(0))
        payload.append(bigEndian(0))
        payload.append(bigEndian(0))
        payload.append(bigEndian(0))
        payload.append(bigEndian(UInt32(cover.count)))
        payload.append(cover)
        return payload
    }

    private static func flacBlock(type: UInt8, payload: Data, isLast: Bool) -> Data {
        guard payload.count <= 0x00ff_ffff else { return Data() }
        var block = Data([type | (isLast ? 0x80 : 0)])
        block.append(contentsOf: [
            UInt8((payload.count >> 16) & 0xff),
            UInt8((payload.count >> 8) & 0xff),
            UInt8(payload.count & 0xff)
        ])
        block.append(payload)
        return block
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

private struct ParsedNCM {
    let keyBox: [UInt8]
    let metadata: NCMAudioMetadata
    let cover: Data
    let audioOffset: UInt64
    let fileSize: UInt64
}

private enum AudioFormat {
    case mp3
    case flac

    var fileExtension: String {
        switch self {
        case .mp3: "mp3"
        case .flac: "flac"
        }
    }
}
