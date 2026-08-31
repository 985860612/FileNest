import CryptoKit
import Foundation
import PDFKit
import Testing
@testable import FileNestKit

@Suite("PDF report self signature")
struct PDFReportSelfSignatureTests {
    @Test("A sealed PDF stays readable and verifies with its signing identity")
    func sealsAndVerifiesPDF() throws {
        let key = P256.Signing.PrivateKey()
        let source = try minimalPDF()

        let sealed = try PDFReportSelfSignature.seal(source, using: key, signedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let result = PDFReportSelfSignature.verify(
            sealed,
            trustedPublicKey: key.publicKey.x963Representation
        )

        #expect(result.status == .validTrusted)
        #expect(result.contentSHA256?.count == 64)
        #expect(result.signedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(PDFDocument(data: sealed)?.pageCount == 1)
        let pdfText = try #require(String(data: sealed, encoding: .isoLatin1))
        #expect(pdfText.contains("/FT /Sig"))
        #expect(pdfText.contains("/Subtype /Widget"))
        #expect(pdfText.contains("/ByteRange ["))
        #expect(pdfText.contains("/SubFilter /adbe.pkcs7.detached"))
        #expect(!pdfText.contains("FILENEST-SELF-SIGNATURE-BEGIN"))
    }

    @Test("Any change to the sealed PDF is detected")
    func detectsModification() throws {
        let key = P256.Signing.PrivateKey()
        var sealed = try PDFReportSelfSignature.seal(try minimalPDF(), using: key)
        sealed[10] ^= 0x01

        #expect(PDFReportSelfSignature.verify(sealed).status == .modified)
    }

    @Test("A valid report from another device remains explicitly self-signed")
    func distinguishesAnotherIdentity() throws {
        let sealed = try PDFReportSelfSignature.seal(
            try minimalPDF(),
            using: P256.Signing.PrivateKey()
        )
        let localKey = P256.Signing.PrivateKey()

        #expect(PDFReportSelfSignature.verify(
            sealed,
            trustedPublicKey: localKey.publicKey.x963Representation
        ).status == .validSelfSigned)
    }

    @Test("An ordinary PDF is reported as unsigned")
    func detectsUnsignedPDF() throws {
        #expect(PDFReportSelfSignature.verify(try minimalPDF()).status == .unsigned)
    }

    @Test("HTML verification report exports as a readable sealed PDF")
    @MainActor
    func exportsHTMLReport() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        let key = P256.Signing.PrivateKey()

        try await PDFSignatureReportExporter.exportHTML(
            "<html><body><h1>电子签名验证报告</h1><p>文件未被修改</p></body></html>",
            to: destination,
            privateKey: key
        )

        let data = try Data(contentsOf: destination)
        #expect((PDFDocument(data: data)?.pageCount ?? 0) > 0)
        #expect(PDFReportSelfSignature.verify(
            data,
            trustedPublicKey: key.publicKey.x963Representation
        ).status == .validTrusted)
    }

    @Test("A real signature report can be exported and sealed with the Keychain identity")
    @MainActor
    func exportsRealReportWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["FILENEST_PDF_SIGNATURE_FIXTURE"],
              let outputPath = environment["FILENEST_SIGNED_PDF_REPORT_OUTPUT"] else { return }
        let destination = URL(fileURLWithPath: outputPath)

        try await PDFSignatureReportExporter.exportVerificationReport(
            source: URL(fileURLWithPath: fixturePath),
            to: destination
        )

        let data = try Data(contentsOf: destination)
        let trustedKey = try PDFReportSigningIdentityStore.trustedPublicKey()
        #expect((PDFDocument(data: data)?.pageCount ?? 0) > 0)
        #expect(PDFReportSelfSignature.verify(data, trustedPublicKey: trustedKey).status == .validTrusted)
        print("Self-signed PDF signature report: \(outputPath)")
    }

    private func minimalPDF() throws -> Data {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        document.insert(try #require(PDFPage(image: image)), at: 0)
        return try #require(document.dataRepresentation())
    }
}
