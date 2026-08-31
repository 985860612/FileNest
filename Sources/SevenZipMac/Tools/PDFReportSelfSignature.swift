import CryptoKit
import Foundation
import Security
import WebKit

enum PDFReportSelfSignatureStatus: Equatable, Sendable {
    case validTrusted
    case validSelfSigned
    case modified
    case unsigned
}

struct PDFReportSelfSignatureResult: Equatable, Sendable {
    let status: PDFReportSelfSignatureStatus
    let contentSHA256: String?
    let signedAt: Date?
    let publicKeyFingerprint: String?
}

enum PDFReportSelfSignatureError: LocalizedError {
    case malformedPDF
    case unsupportedPDF
    case malformedKey
    case certificateCreationFailed
    case cms(OSStatus)
    case keychain(OSStatus)
    case signatureTooLarge
    case destinationExists(String)
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .malformedPDF: "PDF 结构无效，无法添加标准数字签名。"
        case .unsupportedPDF: "该 PDF 结构暂不支持标准增量签名。"
        case .malformedKey: "FileNest 报告签名密钥格式无效。"
        case .certificateCreationFailed: "无法创建 FileNest 自签 X.509 证书。"
        case .cms(let status): "无法生成标准 CMS 签名（状态码：\(status)）。"
        case .keychain(let status): "无法访问 FileNest 报告签名身份（状态码：\(status)）。"
        case .signatureTooLarge: "CMS 签名超过 PDF 预留空间。"
        case .destinationExists(let path): "输出文件已存在：\(path)"
        case .renderingFailed: "无法将电子签名验证报告转换为 PDF。"
        }
    }
}

enum PDFReportSelfSignature {
    private static let signerName = "FileNest PDF Report"
    private static let signatureFieldName = "FileNestReportSignature"
    private static let contentsByteCapacity = 32_768
    private static let numberWidth = 20

    static func seal(
        _ pdfData: Data,
        using privateKey: P256.Signing.PrivateKey,
        signedAt: Date = Date()
    ) throws -> Data {
        let material = try StandardPDFSigningIdentity.ephemeral(privateKey: privateKey)
        return try seal(pdfData, identity: material.identity, signedAt: signedAt)
    }

    static func seal(
        _ pdfData: Data,
        identity: SecIdentity,
        signedAt: Date = Date()
    ) throws -> Data {
        let structure = try PDFIncrementalStructure(pdfData)
        let placeholder = String(repeating: "0", count: contentsByteCapacity * 2)
        let blankNumber = String(repeating: "0", count: numberWidth)
        let byteRangePlaceholder = "/ByteRange [\(blankNumber) \(blankNumber) \(blankNumber) \(blankNumber)]"
        let fieldObject = structure.size
        let signatureObject = structure.size + 1
        let updatedCatalog = try structure.catalogAddingSignatureField(fieldObject)
        let signedDate = pdfDate(signedAt)

        var output = pdfData
        if output.last != 0x0A { output.append(0x0A) }
        let catalogOffset = output.count
        appendASCII("\(structure.rootObject) \(structure.rootGeneration) obj\n", to: &output)
        output.append(updatedCatalog)
        appendASCII("\nendobj\n", to: &output)

        let fieldOffset = output.count
        appendASCII(
            "\(fieldObject) 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Sig /T (\(signatureFieldName)) /Rect [0 0 1 1] /F 194 /Ff 0 /V \(signatureObject) 0 R >>\nendobj\n",
            to: &output
        )

        let signatureOffset = output.count
        appendASCII(
            "\(signatureObject) 0 obj\n<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached \(byteRangePlaceholder) /Contents <\(placeholder)> /M (\(signedDate)) /Name (\(signerName)) /Reason (FileNest signature verification report) >>\nendobj\n",
            to: &output
        )

        let xrefOffset = output.count
        appendASCII("xref\n", to: &output)
        appendXrefSubsection(object: structure.rootObject, offset: catalogOffset, generation: structure.rootGeneration, to: &output)
        appendASCII("\(fieldObject) 2\n", to: &output)
        appendASCII(String(format: "%010d 00000 n \n", fieldOffset), to: &output)
        appendASCII(String(format: "%010d 00000 n \n", signatureOffset), to: &output)
        appendASCII(
            "trailer\n<< /Size \(structure.size + 2) /Root \(structure.rootObject) \(structure.rootGeneration) R /Prev \(structure.previousXref) >>\nstartxref\n\(xrefOffset)\n%%EOF\n",
            to: &output
        )

        guard let byteRangeToken = output.range(of: Data(byteRangePlaceholder.utf8), options: .backwards),
              let contentsPrefix = output.range(of: Data("/Contents <".utf8), options: .backwards) else {
            throw PDFReportSelfSignatureError.malformedPDF
        }
        let contentsOpen = output.index(before: contentsPrefix.upperBound)
        let hexStart = output.index(after: contentsOpen)
        let contentsClose = output.index(hexStart, offsetBy: contentsByteCapacity * 2)
        guard contentsClose < output.endIndex, output[contentsClose] == UInt8(ascii: ">") else {
            throw PDFReportSelfSignatureError.malformedPDF
        }
        let secondRangeStart = output.index(after: contentsClose)
        let byteRanges = [0, contentsOpen, secondRangeStart, output.count - secondRangeStart]
        let byteRangeValue = "/ByteRange [" + byteRanges.map(fixedWidthNumber).joined(separator: " ") + "]"
        guard byteRangeValue.utf8.count == byteRangePlaceholder.utf8.count else {
            throw PDFReportSelfSignatureError.malformedPDF
        }
        output.replaceSubrange(byteRangeToken, with: byteRangeValue.utf8)

        var protectedContent = Data(output[..<contentsOpen])
        protectedContent.append(output[secondRangeStart...])
        let cms = try detachedCMS(content: protectedContent, identity: identity)
        guard cms.count <= contentsByteCapacity else { throw PDFReportSelfSignatureError.signatureTooLarge }
        let cmsHex = cms.map { String(format: "%02X", $0) }.joined()
        let paddedCMSHex = cmsHex + String(repeating: "0", count: contentsByteCapacity * 2 - cmsHex.count)
        output.replaceSubrange(hexStart..<contentsClose, with: paddedCMSHex.utf8)
        return output
    }

    static func verify(
        _ signedPDF: Data,
        trustedPublicKey: Data? = nil
    ) -> PDFReportSelfSignatureResult {
        guard signedPDF.range(of: Data("/T (\(signatureFieldName))".utf8), options: .backwards) != nil else {
            return emptyResult(.unsigned)
        }
        guard let parsed = parseSignature(in: signedPDF),
              parsed.ranges.count == 2,
              parsed.ranges[0].lowerBound == 0,
              parsed.ranges[1].upperBound == signedPDF.count else {
            return emptyResult(.modified)
        }
        var protectedContent = Data()
        for range in parsed.ranges { protectedContent.append(signedPDF[range]) }
        let cms = trimASN1Padding(parsed.cms) ?? parsed.cms
        guard let cmsResult = verifyCMS(cms, detachedContent: protectedContent) else {
            return emptyResult(.modified)
        }
        let status: PDFReportSelfSignatureStatus = trustedPublicKey == cmsResult.publicKey
            ? .validTrusted
            : .validSelfSigned
        return PDFReportSelfSignatureResult(
            status: status,
            contentSHA256: sha256Hex(protectedContent),
            signedAt: parsed.signedAt,
            publicKeyFingerprint: sha256Hex(cmsResult.publicKey)
        )
    }

    private static func detachedCMS(content: Data, identity: SecIdentity) throws -> Data {
        var encoder: CMSEncoder?
        var status = CMSEncoderCreate(&encoder)
        guard status == errSecSuccess, let encoder else { throw PDFReportSelfSignatureError.cms(status) }
        status = CMSEncoderAddSigners(encoder, identity)
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.cms(status) }
        status = CMSEncoderSetHasDetachedContent(encoder, true)
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.cms(status) }
        status = CMSEncoderSetSignerAlgorithm(encoder, kCMSEncoderDigestAlgorithmSHA256)
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.cms(status) }
        status = CMSEncoderSetCertificateChainMode(encoder, CMSCertificateChainMode(rawValue: 1)!)
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.cms(status) }
        status = CMSEncoderAddSignedAttributes(encoder, CMSSignedAttributes(rawValue: 0x0008))
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.cms(status) }
        status = content.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return CMSEncoderUpdateContent(encoder, baseAddress, bytes.count)
        }
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.cms(status) }
        var encoded: CFData?
        status = CMSEncoderCopyEncodedContent(encoder, &encoded)
        guard status == errSecSuccess, let encoded else { throw PDFReportSelfSignatureError.cms(status) }
        return encoded as Data
    }

    private struct CMSVerification { let publicKey: Data }

    private static func verifyCMS(_ cms: Data, detachedContent: Data) -> CMSVerification? {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder,
              CMSDecoderSetDetachedContent(decoder, detachedContent as CFData) == errSecSuccess else { return nil }
        let updateStatus = cms.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, baseAddress, bytes.count)
        }
        guard updateStatus == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
        var signerStatus = CMSSignerStatus(rawValue: 0)!
        var trust: SecTrust?
        guard CMSDecoderCopySignerStatus(
            decoder, 0, SecPolicyCreateBasicX509(), false, &signerStatus, &trust, nil
        ) == errSecSuccess,
              signerStatus == CMSSignerStatus(rawValue: 1),
              let certificate = copySignerCertificate(decoder),
              let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return CMSVerification(publicKey: keyData)
    }

    private static func copySignerCertificate(_ decoder: CMSDecoder) -> SecCertificate? {
        var certificate: SecCertificate?
        guard CMSDecoderCopySignerCert(decoder, 0, &certificate) == errSecSuccess else { return nil }
        return certificate
    }

    private struct ParsedSignature {
        let ranges: [Range<Int>]
        let cms: Data
        let signedAt: Date?
    }

    private static func parseSignature(in data: Data) -> ParsedSignature? {
        guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
        let pattern = #"/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]"#
        guard let match = lastMatch(pattern: pattern, in: text),
              let firstOffset = captureInt(1, match: match, text: text),
              let firstLength = captureInt(2, match: match, text: text),
              let secondOffset = captureInt(3, match: match, text: text),
              let secondLength = captureInt(4, match: match, text: text),
              firstOffset >= 0, firstLength >= 0, secondOffset >= 0, secondLength >= 0,
              firstOffset <= data.count, firstLength <= data.count - firstOffset,
              secondOffset <= data.count, secondLength <= data.count - secondOffset else { return nil }
        guard let contentsPrefix = data.range(of: Data("/Contents <".utf8), options: .backwards) else { return nil }
        let hexStart = contentsPrefix.upperBound
        guard let close = data[hexStart...].firstIndex(of: UInt8(ascii: ">")) else { return nil }
        let hex = data[hexStart..<close].filter { !$0.isASCIIWhitespace }
        guard hex.count.isMultiple(of: 2), let cms = decodeHex(Array(hex)) else { return nil }
        let signedAt = captureString(pattern: #"/M\s*\(D:(\d{14})Z\)"#, in: text).flatMap(parsePDFDate)
        return ParsedSignature(
            ranges: [firstOffset..<(firstOffset + firstLength), secondOffset..<(secondOffset + secondLength)],
            cms: cms,
            signedAt: signedAt
        )
    }

    private static func decodeHex(_ bytes: [UInt8]) -> Data? {
        var result = Data(capacity: bytes.count / 2)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = hexValue(bytes[index]), let low = hexValue(bytes[index + 1]) else { return nil }
            result.append(high << 4 | low)
        }
        return result
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    private static func trimASN1Padding(_ data: Data) -> Data? {
        guard data.count >= 2, data[0] == 0x30 else { return nil }
        let first = Int(data[1])
        let contentLength: Int
        let headerLength: Int
        if first & 0x80 == 0 {
            contentLength = first; headerLength = 2
        } else {
            let count = first & 0x7F
            guard count > 0, count <= MemoryLayout<Int>.size, data.count >= 2 + count else { return nil }
            var length = 0
            for byte in data[2..<(2 + count)] { length = (length << 8) | Int(byte) }
            contentLength = length; headerLength = 2 + count
        }
        guard headerLength + contentLength <= data.count else { return nil }
        return Data(data.prefix(headerLength + contentLength))
    }

    private static func lastMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last
    }

    private static func captureInt(_ index: Int, match: NSTextCheckingResult, text: String) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func captureString(pattern: String, in text: String) -> String? {
        guard let match = lastMatch(pattern: pattern, in: text),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func parsePDFDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: value)
    }

    private static func pdfDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMddHHmmss"
        return "D:\(formatter.string(from: date))Z"
    }

    private static func fixedWidthNumber(_ number: Int) -> String {
        String(format: "%0*d", numberWidth, number)
    }

    private static func appendXrefSubsection(object: Int, offset: Int, generation: Int, to data: inout Data) {
        appendASCII("\(object) 1\n", to: &data)
        appendASCII(String(format: "%010d %05d n \n", offset, generation), to: &data)
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func emptyResult(_ status: PDFReportSelfSignatureStatus) -> PDFReportSelfSignatureResult {
        PDFReportSelfSignatureResult(status: status, contentSHA256: nil, signedAt: nil, publicKeyFingerprint: nil)
    }
}

private struct PDFIncrementalStructure {
    let rootObject: Int
    let rootGeneration: Int
    let size: Int
    let previousXref: Int
    let catalog: Data

    init(_ data: Data) throws {
        guard data.starts(with: Data("%PDF-".utf8)),
              let text = String(data: data, encoding: .isoLatin1),
              let root = Self.lastCaptures(#"/Root\s+(\d+)\s+(\d+)\s+R"#, in: text),
              let rootObject = Int(root[0]), let rootGeneration = Int(root[1]),
              let sizeCapture = Self.lastCaptures(#"/Size\s+(\d+)"#, in: text)?.first,
              let size = Int(sizeCapture),
              let xrefCapture = Self.lastCaptures(#"startxref\s+(\d+)\s+%%EOF"#, in: text)?.first,
              let previousXref = Int(xrefCapture),
              let catalog = Self.objectDictionary(data: data, object: rootObject, generation: rootGeneration) else {
            throw PDFReportSelfSignatureError.malformedPDF
        }
        guard catalog.range(of: Data("/AcroForm".utf8)) == nil else {
            throw PDFReportSelfSignatureError.unsupportedPDF
        }
        self.rootObject = rootObject
        self.rootGeneration = rootGeneration
        self.size = size
        self.previousXref = previousXref
        self.catalog = catalog
    }

    func catalogAddingSignatureField(_ fieldObject: Int) throws -> Data {
        guard catalog.count >= 4, catalog.suffix(2) == Data(">>".utf8) else {
            throw PDFReportSelfSignatureError.malformedPDF
        }
        var updated = Data(catalog.dropLast(2))
        updated.append(contentsOf: "\n/AcroForm << /SigFlags 3 /Fields [\(fieldObject) 0 R] >>\n>>".utf8)
        return updated
    }

    private static func lastCaptures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func objectDictionary(data: Data, object: Int, generation: Int) -> Data? {
        let header = Data("\(object) \(generation) obj".utf8)
        guard let headerRange = data.range(of: header, options: .backwards),
              let start = data.range(of: Data("<<".utf8), in: headerRange.upperBound..<data.endIndex)?.lowerBound else { return nil }
        var cursor = start
        var depth = 0
        while cursor + 1 < data.endIndex {
            if data[cursor] == UInt8(ascii: "<"), data[cursor + 1] == UInt8(ascii: "<") {
                depth += 1; cursor += 2; continue
            }
            if data[cursor] == UInt8(ascii: ">"), data[cursor + 1] == UInt8(ascii: ">") {
                depth -= 1; cursor += 2
                if depth == 0 { return Data(data[start..<cursor]) }
                continue
            }
            cursor += 1
        }
        return nil
    }
}

private struct StandardPDFSigningIdentity {
    let identity: SecIdentity

    static func ephemeral(privateKey: P256.Signing.PrivateKey) throws -> StandardPDFSigningIdentity {
        try create(privateKey: privateKey, certificateData: SelfSignedCertificate.create(privateKey: privateKey))
    }

    static func create(privateKey: P256.Signing.PrivateKey, certificateData: Data) throws -> StandardPDFSigningIdentity {
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw PDFReportSelfSignatureError.certificateCreationFailed
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256
        ]
        guard let secKey = SecKeyCreateWithData(
            privateKey.x963Representation as CFData, attributes as CFDictionary, nil
        ), let identity = SecIdentityCreate(nil, certificate, secKey) else {
            throw PDFReportSelfSignatureError.malformedKey
        }
        return StandardPDFSigningIdentity(identity: identity)
    }
}

private enum SelfSignedCertificate {
    static func create(privateKey: P256.Signing.PrivateKey, now: Date = Date()) throws -> Data {
        let signatureAlgorithm = DER.sequence(DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
        let commonName = DER.sequence(
            DER.set(DER.sequence(DER.oid([0x55, 0x04, 0x03]) + DER.utf8String("FileNest PDF Report")))
        )
        let publicKeyAlgorithm = DER.sequence(
            DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]) +
            DER.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        )
        let subjectPublicKeyInfo = DER.sequence(publicKeyAlgorithm + DER.bitString(privateKey.publicKey.x963Representation))
        var serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        serial[serial.startIndex] &= 0x7F
        if serial.allSatisfy({ $0 == 0 }) { serial[serial.startIndex] = 1 }
        let notBefore = now.addingTimeInterval(-86_400)
        let notAfter = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: now)!
        let validity = DER.sequence(DER.utcTime(notBefore) + DER.utcTime(notAfter))
        let basicConstraints = DER.sequence(
            DER.oid([0x55, 0x1D, 0x13]) + DER.octetString(DER.sequence(Data()))
        )
        let keyUsage = DER.sequence(
            DER.oid([0x55, 0x1D, 0x0F]) + DER.boolean(true) +
            DER.octetString(DER.bitString(Data([0x80]), unusedBits: 7))
        )
        let extensions = DER.tagged(0xA3, DER.sequence(basicConstraints + keyUsage))
        let tbs = DER.sequence(
            DER.tagged(0xA0, DER.integer(Data([0x02]))) + DER.integer(serial) +
            signatureAlgorithm + commonName + validity + commonName + subjectPublicKeyInfo + extensions
        )
        let signature = try privateKey.signature(for: tbs)
        return DER.sequence(tbs + signatureAlgorithm + DER.bitString(signature.derRepresentation))
    }
}

private enum DER {
    static func sequence(_ content: Data) -> Data { tagged(0x30, content) }
    static func set(_ content: Data) -> Data { tagged(0x31, content) }
    static func octetString(_ content: Data) -> Data { tagged(0x04, content) }
    static func utf8String(_ value: String) -> Data { tagged(0x0C, Data(value.utf8)) }
    static func boolean(_ value: Bool) -> Data { tagged(0x01, Data([value ? 0xFF : 0x00])) }
    static func oid(_ content: [UInt8]) -> Data { tagged(0x06, Data(content)) }

    static func integer(_ bytes: Data) -> Data {
        var content = Data(bytes.drop(while: { $0 == 0 }))
        if content.isEmpty { content = Data([0]) }
        if content[0] & 0x80 != 0 { content.insert(0, at: 0) }
        return tagged(0x02, content)
    }

    static func bitString(_ content: Data, unusedBits: UInt8 = 0) -> Data {
        tagged(0x03, Data([unusedBits]) + content)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }

    static func tagged(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + encodedLength(content.count) + content
    }

    private static func encodedLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var value = length
        var bytes: [UInt8] = []
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}

enum PDFReportSigningIdentityStore {
    private static let service = "com.filenest.pdf-report-signing"
    private static let keyAccount = "default-p256-signing-key"
    private static let certificateAccount = "default-self-signed-x509"

    static func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
        if let data = try loadData(account: keyAccount) {
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: data) else {
                throw PDFReportSelfSignatureError.malformedKey
            }
            return key
        }
        let key = P256.Signing.PrivateKey()
        try saveData(key.rawRepresentation, account: keyAccount)
        return key
    }

    fileprivate static func loadOrCreateIdentity() throws -> StandardPDFSigningIdentity {
        let key = try loadOrCreatePrivateKey()
        if let certificateData = try loadData(account: certificateAccount),
           let material = try? StandardPDFSigningIdentity.create(privateKey: key, certificateData: certificateData) {
            return material
        }
        let certificateData = try SelfSignedCertificate.create(privateKey: key)
        try upsertData(certificateData, account: certificateAccount)
        return try StandardPDFSigningIdentity.create(privateKey: key, certificateData: certificateData)
    }

    static func trustedPublicKey() throws -> Data? {
        guard let data = try loadData(account: keyAccount),
              let key = try? P256.Signing.PrivateKey(rawRepresentation: data) else { return nil }
        return key.publicKey.x963Representation
    }

    private static func loadData(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw PDFReportSelfSignatureError.keychain(status)
        }
        return data
    }

    private static func saveData(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.keychain(status) }
    }

    private static func upsertData(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound { try saveData(data, account: account); return }
        guard status == errSecSuccess else { throw PDFReportSelfSignatureError.keychain(status) }
    }
}

@MainActor
enum PDFSignatureReportExporter {
    static func exportVerificationReport(source: URL, to destination: URL) async throws {
        let signatures = try PDFSignatureService.extractSignatures(from: source)
        let html = try PDFSignatureReportRenderer.render(fileURL: source, signatures: signatures)
        try await exportHTML(html, to: destination)
    }

    static func exportHTML(
        _ html: String,
        to destination: URL,
        privateKey: P256.Signing.PrivateKey? = nil
    ) async throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PDFReportSelfSignatureError.destinationExists(destination.path)
        }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900))
        let navigation = NavigationWaiter()
        webView.navigationDelegate = navigation
        try await navigation.load(html, in: webView)
        let height = try await documentHeight(in: webView)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 1280, height: max(900, height))
        let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: configuration) { result in continuation.resume(with: result) }
        }
        guard pdfData.starts(with: Data("%PDF-".utf8)) else { throw PDFReportSelfSignatureError.renderingFailed }
        let signed: Data
        if let privateKey {
            signed = try PDFReportSelfSignature.seal(pdfData, using: privateKey)
        } else {
            let material = try PDFReportSigningIdentityStore.loadOrCreateIdentity()
            signed = try PDFReportSelfSignature.seal(pdfData, identity: material.identity)
        }
        try signed.write(to: destination, options: .atomic)
    }

    private static func documentHeight(in webView: WKWebView) async throws -> CGFloat {
        let height: Double = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(
                "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
            ) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let number = value as? NSNumber { continuation.resume(returning: number.doubleValue) }
                else { continuation.resume(throwing: PDFReportSelfSignatureError.renderingFailed) }
            }
        }
        return CGFloat(height)
    }

    @MainActor
    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func load(_ html: String, in webView: WKWebView) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.loadHTMLString(html, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume(); continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error); continuation = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            continuation?.resume(throwing: error); continuation = nil
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}
