import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PDFKit
import Security

struct PDFSignatureByteRange: Equatable, Sendable {
    let offset: Int
    let length: Int
}

struct PDFSignatureInfo: Identifiable, Equatable, Sendable {
    let index: Int
    let fieldName: String
    let subFilter: String
    let signerCommonName: String
    let signerOrganization: String
    let signerOrganizationalUnit: String
    let certificateSerialNumber: String
    let certificateIssuerCommonName: String
    let certificateNotBefore: Date?
    let certificateNotAfter: Date?
    let signingTime: Date?
    let byteRanges: [PDFSignatureByteRange]
    let protectedContentHashBase64: String
    let appearanceImagePNG: Data?
    let protectedContentDigestMatches: Bool
    let certificateTrustedBySystem: Bool
    let coversWholeDocument: Bool

    var id: String { "\(index)-\(fieldName)" }
}

enum PDFSignatureError: LocalizedError {
    case unreadablePDF(String)
    case missingForm
    case malformedSignature(String)
    case certificateUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let path): "无法读取 PDF：\(path)"
        case .missingForm: "PDF 不包含可读取的签名表单。"
        case .malformedSignature(let field): "签名域格式无效：\(field)"
        case .certificateUnavailable(let field): "无法从签名域提取证书：\(field)"
        }
    }
}

enum PDFSignatureService {
    static func extractSignatures(from fileURL: URL) throws -> [PDFSignatureInfo] {
        guard let provider = CGDataProvider(url: fileURL as CFURL),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog else {
            throw PDFSignatureError.unreadablePDF(fileURL.path)
        }

        var acroForm: CGPDFDictionaryRef?
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm),
              let acroForm,
              CGPDFDictionaryGetArray(acroForm, "Fields", &fields),
              let fields else {
            throw PDFSignatureError.missingForm
        }

        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let fileSize = fileData.count
        let appearanceImages = signatureAppearanceImages(from: fileURL)
        var rawSignatures: [RawSignature] = []
        for fieldIndex in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(fields, fieldIndex, &field), let field {
                collectSignatures(in: field, inheritedName: nil, inheritedType: nil, into: &rawSignatures)
            }
        }

        let sorted = rawSignatures.sorted {
            signedDocumentEnd($0.byteRanges) < signedDocumentEnd($1.byteRanges)
        }
        return try sorted.enumerated().map { offset, raw in
            let protectedContent = try protectedContent(from: fileData, ranges: raw.byteRanges, fieldName: raw.fieldName)
            guard let cms = decodeCMS(raw.contents, detachedContent: protectedContent),
                  !cms.certificate.commonName.isEmpty else {
                throw PDFSignatureError.certificateUnavailable(raw.fieldName)
            }
            return PDFSignatureInfo(
                index: offset + 1,
                fieldName: raw.fieldName,
                subFilter: raw.subFilter,
                signerCommonName: cms.certificate.commonName,
                signerOrganization: cms.certificate.organization,
                signerOrganizationalUnit: cms.certificate.organizationalUnit,
                certificateSerialNumber: cms.certificate.serialNumber,
                certificateIssuerCommonName: cms.certificate.issuerCommonName,
                certificateNotBefore: cms.certificate.notBefore,
                certificateNotAfter: cms.certificate.notAfter,
                signingTime: parsePDFDate(raw.signingTime),
                byteRanges: raw.byteRanges,
                protectedContentHashBase64: Data(SHA256.hash(data: protectedContent)).base64EncodedString(),
                appearanceImagePNG: appearanceImages[raw.fieldName],
                protectedContentDigestMatches: cms.protectedContentDigestMatches,
                certificateTrustedBySystem: cms.certificateTrustedBySystem,
                coversWholeDocument: signedDocumentEnd(raw.byteRanges) == fileSize
            )
        }
    }

    private struct RawSignature {
        let fieldName: String
        let subFilter: String
        let signingTime: String?
        let byteRanges: [PDFSignatureByteRange]
        let contents: Data
    }

    private static func collectSignatures(
        in field: CGPDFDictionaryRef,
        inheritedName: String?,
        inheritedType: String?,
        into signatures: inout [RawSignature]
    ) {
        let fieldName = pdfString(in: field, key: "T") ?? inheritedName ?? "未命名签名域"
        let fieldType = pdfName(in: field, key: "FT") ?? inheritedType

        var value: CGPDFDictionaryRef?
        if fieldType == "Sig", CGPDFDictionaryGetDictionary(field, "V", &value), let value,
           let contents = pdfData(in: value, key: "Contents"),
           let byteRanges = pdfByteRanges(in: value), !byteRanges.isEmpty {
            signatures.append(RawSignature(
                fieldName: fieldName,
                subFilter: pdfName(in: value, key: "SubFilter") ?? "",
                signingTime: pdfString(in: value, key: "M"),
                byteRanges: byteRanges,
                contents: trimASN1Padding(contents)
            ))
        }

        var kids: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(field, "Kids", &kids), let kids else { return }
        for index in 0..<CGPDFArrayGetCount(kids) {
            var child: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(kids, index, &child), let child {
                collectSignatures(
                    in: child,
                    inheritedName: fieldName,
                    inheritedType: fieldType,
                    into: &signatures
                )
            }
        }
    }

    private static func pdfString(in dictionary: CGPDFDictionaryRef, key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }

    private static func pdfName(in dictionary: CGPDFDictionaryRef, key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }

    private static func pdfData(in dictionary: CGPDFDictionaryRef, key: String) -> Data? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value,
              let bytes = CGPDFStringGetBytePtr(value) else { return nil }
        return Data(bytes: bytes, count: CGPDFStringGetLength(value))
    }

    private static func pdfByteRanges(in dictionary: CGPDFDictionaryRef) -> [PDFSignatureByteRange]? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "ByteRange", &array), let array,
              CGPDFArrayGetCount(array).isMultiple(of: 2) else { return nil }
        var values: [Int] = []
        for index in 0..<CGPDFArrayGetCount(array) {
            var value: CGPDFInteger = 0
            guard CGPDFArrayGetInteger(array, index, &value), value >= 0 else { return nil }
            values.append(Int(value))
        }
        return stride(from: 0, to: values.count, by: 2).map {
            PDFSignatureByteRange(offset: values[$0], length: values[$0 + 1])
        }
    }

    private static func signedDocumentEnd(_ ranges: [PDFSignatureByteRange]) -> Int {
        ranges.map { $0.offset + $0.length }.max() ?? 0
    }

    private static func protectedContent(
        from fileData: Data,
        ranges: [PDFSignatureByteRange],
        fieldName: String
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(ranges.reduce(0) { $0 + $1.length })
        for range in ranges {
            guard range.offset >= 0, range.length >= 0,
                  range.offset <= fileData.count,
                  range.length <= fileData.count - range.offset else {
                throw PDFSignatureError.malformedSignature(fieldName)
            }
            result.append(fileData[range.offset..<(range.offset + range.length)])
        }
        return result
    }

    private static func trimASN1Padding(_ data: Data) -> Data {
        guard data.count >= 2, data[0] == 0x30 else { return data }
        let lengthByte = Int(data[1])
        let contentLength: Int
        let headerLength: Int
        if lengthByte & 0x80 == 0 {
            contentLength = lengthByte
            headerLength = 2
        } else {
            let lengthOctets = lengthByte & 0x7F
            guard lengthOctets > 0, lengthOctets <= MemoryLayout<Int>.size,
                  data.count >= 2 + lengthOctets else { return data }
            var parsedLength = 0
            for byte in data[2..<(2 + lengthOctets)] {
                parsedLength = (parsedLength << 8) | Int(byte)
            }
            contentLength = parsedLength
            headerLength = 2 + lengthOctets
        }
        let totalLength = headerLength + contentLength
        guard totalLength <= data.count else { return data }
        return data.prefix(totalLength)
    }

    private static func signatureAppearanceImages(from fileURL: URL) -> [String: Data] {
        guard let document = PDFDocument(url: fileURL) else { return [:] }
        var images: [String: Data] = [:]
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.widgetFieldType == .signature {
                guard let fieldName = annotation.fieldName, !fieldName.isEmpty,
                      let png = renderAppearance(annotation) else { continue }
                images[fieldName] = png
            }
        }
        return images
    }

    private static func renderAppearance(_ annotation: PDFAnnotation) -> Data? {
        let bounds = annotation.bounds.standardized
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(4, 320 / max(bounds.width, bounds.height))
        let width = max(1, Int(ceil(bounds.width * scale)))
        let height = max(1, Int(ceil(bounds.height * scale)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        annotation.draw(with: .mediaBox, in: context)
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private struct CertificateInfo {
        let commonName: String
        let organization: String
        let organizationalUnit: String
        let serialNumber: String
        let issuerCommonName: String
        let notBefore: Date?
        let notAfter: Date?
    }

    private struct CMSInfo {
        let certificate: CertificateInfo
        let protectedContentDigestMatches: Bool
        let certificateTrustedBySystem: Bool
    }

    private static func decodeCMS(_ cmsData: Data, detachedContent: Data) -> CMSInfo? {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
        guard CMSDecoderSetDetachedContent(decoder, detachedContent as CFData) == errSecSuccess else { return nil }
        let updateStatus = cmsData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, baseAddress, bytes.count)
        }
        guard updateStatus == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return nil }
        var certificate: SecCertificate?
        guard CMSDecoderCopySignerCert(decoder, 0, &certificate) == errSecSuccess,
              let certificate else { return nil }
        let policy = SecPolicyCreateBasicX509()
        var signerStatus = CMSSignerStatus(rawValue: 0)!
        var trust: SecTrust?
        guard CMSDecoderCopySignerStatus(
            decoder, 0, policy, false, &signerStatus, &trust, nil
        ) == errSecSuccess else { return nil }
        var certificateTrusted = false
        if let trust {
            SecTrustSetNetworkFetchAllowed(trust, false)
            certificateTrusted = SecTrustEvaluateWithError(trust, nil)
        }
        let values = SecCertificateCopyValues(certificate, [
            kSecOIDX509V1SubjectName,
            kSecOIDX509V1IssuerName,
            kSecOIDX509V1ValidityNotBefore,
            kSecOIDX509V1ValidityNotAfter
        ] as CFArray, nil) as NSDictionary?
        let subjectValues = certificateValue(kSecOIDX509V1SubjectName, in: values) as? [NSDictionary]
        let issuerValues = certificateValue(kSecOIDX509V1IssuerName, in: values) as? [NSDictionary]
        let serialData = SecCertificateCopySerialNumberData(certificate, nil) as Data? ?? Data()
        return CMSInfo(
            certificate: CertificateInfo(
                commonName: SecCertificateCopySubjectSummary(certificate) as String? ?? "",
                organization: subjectStringValue(kSecOIDOrganizationName, in: subjectValues),
                organizationalUnit: subjectStringValue(kSecOIDOrganizationalUnitName, in: subjectValues),
                serialNumber: serialData.map { String(format: "%02x", $0) }.joined(),
                issuerCommonName: subjectStringValue(kSecOIDCommonName, in: issuerValues),
                notBefore: certificateDateValue(kSecOIDX509V1ValidityNotBefore, in: values),
                notAfter: certificateDateValue(kSecOIDX509V1ValidityNotAfter, in: values)
            ),
            protectedContentDigestMatches: signedMessageDigest(in: cmsData).map {
                digest(detachedContent, matchingByteCount: $0.count) == $0
            } ?? false,
            certificateTrustedBySystem: certificateTrusted
        )
    }

    private static func signedMessageDigest(in cmsData: Data) -> Data? {
        let messageDigestOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04])
        guard let oidRange = cmsData.range(of: messageDigestOID),
              let valueSet = derElement(in: cmsData, at: oidRange.upperBound),
              valueSet.tag == 0x31,
              let octetString = derElement(in: cmsData, at: valueSet.contentRange.lowerBound),
              octetString.tag == 0x04 else { return nil }
        return Data(cmsData[octetString.contentRange])
    }

    private static func digest(_ data: Data, matchingByteCount byteCount: Int) -> Data? {
        switch byteCount {
        case 20: Data(Insecure.SHA1.hash(data: data))
        case 32: Data(SHA256.hash(data: data))
        case 48: Data(SHA384.hash(data: data))
        case 64: Data(SHA512.hash(data: data))
        default: nil
        }
    }

    private struct DERElement {
        let tag: UInt8
        let contentRange: Range<Data.Index>
    }

    private static func derElement(in data: Data, at offset: Data.Index) -> DERElement? {
        guard offset >= data.startIndex, offset < data.endIndex else { return nil }
        let tag = data[offset]
        var cursor = data.index(after: offset)
        guard cursor < data.endIndex else { return nil }
        let firstLengthByte = Int(data[cursor])
        cursor = data.index(after: cursor)

        let contentLength: Int
        if firstLengthByte & 0x80 == 0 {
            contentLength = firstLengthByte
        } else {
            let lengthByteCount = firstLengthByte & 0x7F
            guard lengthByteCount > 0, lengthByteCount <= MemoryLayout<Int>.size,
                  data.distance(from: cursor, to: data.endIndex) >= lengthByteCount else { return nil }
            var parsedLength = 0
            for _ in 0..<lengthByteCount {
                parsedLength = (parsedLength << 8) | Int(data[cursor])
                cursor = data.index(after: cursor)
            }
            contentLength = parsedLength
        }

        guard contentLength >= 0,
              data.distance(from: cursor, to: data.endIndex) >= contentLength else { return nil }
        return DERElement(
            tag: tag,
            contentRange: cursor..<data.index(cursor, offsetBy: contentLength)
        )
    }

    private static func subjectStringValue(_ oid: CFString, in items: [NSDictionary]?) -> String {
        guard let item = items?.first(where: {
            ($0[kSecPropertyKeyLabel as String] as? String) == (oid as String)
        }) else { return "" }
        return item[kSecPropertyKeyValue as String] as? String ?? ""
    }

    private static func certificateDateValue(_ oid: CFString, in values: NSDictionary?) -> Date? {
        if let date = certificateValue(oid, in: values) as? Date { return date }
        if let seconds = certificateValue(oid, in: values) as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
        }
        return nil
    }

    private static func certificateValue(_ oid: CFString, in values: NSDictionary?) -> Any? {
        guard let property = values?[oid as String] as? NSDictionary else { return nil }
        return property[kSecPropertyKeyValue as String]
    }

    private static func parsePDFDate(_ value: String?) -> Date? {
        guard var value, !value.isEmpty else { return nil }
        if value.hasPrefix("D:") { value.removeFirst(2) }
        let pattern = #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:([Zz])|([+-])(\d{2})'?((?:\d{2})?)'?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return nil
        }
        func component(_ index: Int) -> Int? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return nil }
            return Int(value[swiftRange])
        }
        guard let year = component(1), let month = component(2), let day = component(3),
              let hour = component(4), let minute = component(5), let second = component(6) else { return nil }
        var secondsFromGMT = 0
        if match.range(at: 7).location == NSNotFound, let offsetHours = component(9) {
            let signRange = match.range(at: 8)
            let sign = signRange.location != NSNotFound && Range(signRange, in: value).map { value[$0] == "-" } == true ? -1 : 1
            secondsFromGMT = sign * (offsetHours * 3600 + (component(10) ?? 0) * 60)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? .gmt
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))
    }
}
