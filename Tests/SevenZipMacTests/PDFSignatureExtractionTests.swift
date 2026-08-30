import Foundation
import CoreGraphics
import Testing
@testable import SevenZipMac

@Suite("PDF signature information extraction")
struct PDFSignatureExtractionTests {
    @Test("Extracts every signature field and full certificate subject from a real PDF")
    func extractsRealSignedPDF() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["FILENEST_PDF_SIGNATURE_FIXTURE"] else {
            return
        }

        let fileURL = URL(fileURLWithPath: fixturePath)
        let signatures = try PDFSignatureService.extractSignatures(from: fileURL)

        #expect(signatures.count == 35)
        #expect(Set(signatures.map(\.signerCommonName)).count == 3)
        #expect(signatures.allSatisfy { !$0.signerCommonName.isEmpty })
        #expect(signatures.allSatisfy { $0.signerCommonName.contains("@") })
        #expect(signatures.allSatisfy { $0.signerOrganization == "北京五八信息技术有限公司" })
        #expect(signatures.allSatisfy { $0.signerOrganizationalUnit == "QianWeiShi" })
        #expect(signatures.allSatisfy { $0.certificateNotBefore != nil })
        #expect(signatures.allSatisfy { $0.certificateNotAfter != nil })
        #expect(signatures.allSatisfy { $0.protectedContentDigestMatches })
        #expect(signatures.allSatisfy { !$0.protectedContentHashBase64.isEmpty })
        #expect(signatures.allSatisfy { $0.appearanceImagePNG?.isEmpty == false })
        #expect(signatures.allSatisfy { !$0.certificateSerialNumber.isEmpty })
        #expect(signatures.allSatisfy { $0.certificateIssuerCommonName == "ROOT CERTIFICATE FOR GFA TRUST NETWORK" })
        #expect(signatures.allSatisfy { $0.subFilter == "ETSI.CAdES.detached" })
        #expect(signatures.allSatisfy { $0.signingTime != nil })
        #expect(signatures.dropLast().allSatisfy { !$0.coversWholeDocument })
        #expect(signatures.last?.coversWholeDocument == true)

        let signerCounts = Dictionary(grouping: signatures, by: \.signerCommonName)
            .mapValues(\.count)
        #expect(signerCounts.values.sorted() == [11, 11, 13])

        for (commonName, count) in signerCounts.sorted(by: { $0.key < $1.key }) {
            let signature = signatures.first { $0.signerCommonName == commonName }!
            print(
                "PDF signer CN: \(commonName), signatures: \(count), " +
                "organization: \(signature.signerOrganization), " +
                "unit: \(signature.signerOrganizationalUnit), " +
                "certificate: \(String(describing: signature.certificateNotBefore)) ... " +
                "\(String(describing: signature.certificateNotAfter))"
            )
        }

        let html = try PDFSignatureReportRenderer.render(fileURL: fileURL, signatures: signatures)
        #expect(html.contains("文件验证结果"))
        #expect(html.contains("文件中共包含35个电子签名"))
        #expect(html.contains("6283365c3590038956fa11474737b06488dc5913f4832fe5d28dd8a7cc7cb069"))
        #expect(html.contains("ROOT CERTIFICATE FOR GFA TRUST NETWORK"))
        #expect(html.contains("文件未被修改"))
        #expect(html.contains("文件自本签名以来未被修改"))
        #expect(html.contains("data:image/png;base64,"))

        if let outputPath = ProcessInfo.processInfo.environment["FILENEST_PDF_SIGNATURE_REPORT_OUTPUT"] {
            try Data(html.utf8).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            print("PDF signature HTML report: \(outputPath)")
        }
    }

    @Test("Rejects a readable PDF without signature fields")
    func rejectsUnsignedPDF() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try #require(CGContext(fileURL as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        #expect(throws: PDFSignatureError.self) {
            try PDFSignatureService.extractSignatures(from: fileURL)
        }
    }
}
