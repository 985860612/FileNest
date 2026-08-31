import CryptoKit
import Foundation

enum PDFSignatureReportRenderer {
    static func render(fileURL: URL, signatures: [PDFSignatureInfo]) throws -> String {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let fileHash = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
        let fileSize = ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file)
        let finalSignatureValid = signatures.last?.coversWholeDocument == true &&
            signatures.last?.protectedContentDigestMatches == true
        let cards = signatures.map(signatureCard).joined(separator: "\n")
        let generatedAt = dateFormatter.string(from: Date())

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>PDF 电子签名验证报告</title>
          <style>
            :root { --green:#13b83f; --orange:#f5a000; --red:#d63b35; --ink:#191919; --muted:#777; --line:#e7e7e7; --panel:#f8f8f8; }
            * { box-sizing:border-box; }
            html,body { margin:0; background:#fff; color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",Arial,sans-serif; }
            body { width:1280px; }
            main { padding:76px 68px 88px; }
            h1,h2,h3,p { margin:0; }
            h1 { font-size:30px; margin-bottom:26px; }
            h2 { font-size:28px; margin-top:92px; margin-bottom:24px; }
            .overall { position:relative; min-height:250px; }
            .headline { display:flex; align-items:center; gap:14px; font-size:23px; font-weight:700; margin-bottom:32px; }
            .icon { width:26px; height:26px; border-radius:50%; display:inline-grid; place-items:center; color:#fff; font-size:17px; font-weight:800; flex:none; }
            .ok { background:var(--green); }
            .bad { background:var(--red); }
            .meta { display:grid; grid-template-columns:160px 1fr; row-gap:18px; font-size:17px; line-height:1.5; max-width:860px; }
            .label { color:var(--muted); }
            .hash { word-break:break-all; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:15px; }
            .stamp { position:absolute; right:88px; top:54px; width:150px; height:150px; border:6px double currentColor; border-radius:50%; display:grid; place-items:center; color:#9cdda9; font-size:28px; font-weight:800; transform:rotate(-10deg); opacity:.9; }
            .summary { font-size:22px; margin-bottom:22px; }
            .card { background:var(--panel); border-radius:18px; padding:30px 28px 30px; margin:0 0 28px; break-inside:avoid; }
            .card-head { display:flex; justify-content:space-between; gap:24px; align-items:flex-start; border-bottom:1px dashed #ddd; padding-bottom:20px; }
            .card-title { font-size:21px; font-weight:700; max-width:720px; word-break:break-all; }
            .status { display:flex; align-items:center; gap:10px; font-size:17px; font-weight:650; white-space:nowrap; }
            .dot { width:20px; height:20px; border-radius:50%; display:inline-grid; place-items:center; color:white; font-size:13px; }
            .card-body { display:grid; grid-template-columns:minmax(0,1fr) 315px; gap:44px; padding-top:24px; }
            .section-title { font-size:16px; font-weight:700; margin:0 0 17px; }
            .rows { display:grid; grid-template-columns:176px minmax(0,1fr); row-gap:13px; font-size:15px; line-height:1.5; }
            .rows .value { word-break:break-all; }
            .notice { display:flex; align-items:flex-start; gap:10px; margin-bottom:14px; font-size:15px; line-height:1.45; }
            .notice-mark { width:18px; height:18px; border:2px solid currentColor; border-radius:50%; display:grid; place-items:center; font-size:11px; font-weight:800; flex:none; margin-top:1px; }
            .notice.good { color:#18883a; }
            .notice.warn { color:#9a6500; }
            .notice.neutral { color:#666; }
            .mini-stamp { width:104px; height:104px; border:4px double #d9d9d9; border-radius:50%; color:#c9c9c9; display:grid; place-items:center; font-size:17px; font-weight:700; transform:rotate(-10deg); margin:24px auto 0; }
            .signature-image-wrap { height:126px; display:flex; align-items:center; justify-content:center; margin:20px auto 0; }
            .signature-image { display:block; max-width:260px; max-height:120px; object-fit:contain; }
            footer { margin-top:48px; padding-top:24px; border-top:1px solid var(--line); color:#777; font-size:14px; line-height:1.75; }
          </style>
        </head>
        <body>
        <main>
          <section class="overall">
            <h1>文件验证结果</h1>
            <div class="headline"><span class="icon \(finalSignatureValid ? "ok" : "bad")">\(finalSignatureValid ? "✓" : "!")</span>\(finalSignatureValid ? "文件未被修改" : "文件完整性校验未通过")</div>
            <div class="meta">
              <div class="label">文件名称：</div><div>\(escape(fileURL.lastPathComponent))</div>
              <div class="label">文件大小：</div><div>\(escape(fileSize))</div>
              <div class="label">当前文件 SHA-256：</div><div class="hash">\(fileHash)</div>
              <div class="label">报告生成时间：</div><div>\(generatedAt)</div>
            </div>
            <div class="stamp">\(finalSignatureValid ? "未被修改" : "待核查")</div>
          </section>

          <section>
            <h2>签名验证结果</h2>
            <p class="summary">文件中共包含\(signatures.count)个电子签名</p>
            \(cards)
          </section>

          <footer>
            本报告由 FileNest 在本机离线生成。导出为 PDF 时，系统使用保存在 macOS 钥匙串中的 P-256 私钥和自签 X.509 证书，写入标准 PDF/CMS 数字签名。Adobe Acrobat 等兼容阅读器可校验报告在签名后是否被修改；由于证书为自签证书，签署人身份默认不受系统信任。该签名不等同于第三方 CA 认证、可信时间戳或 PAdES 长期验证签名。原文件的证书信任验证不联网，不执行在线 OCSP/CRL 查询。
          </footer>
        </main>
        </body>
        </html>
        """
    }

    private static func signatureCard(_ signature: PDFSignatureInfo) -> String {
        let integrityText = signature.protectedContentDigestMatches ? "文件自本签名以来未被修改" : "文件自本签名以来可能已被修改"
        let integrityClass = signature.protectedContentDigestMatches ? "good" : "warn"
        let certExpired = signature.certificateNotAfter.map { $0 < Date() } ?? false
        let coverageNotice = signature.coversWholeDocument
            ? "该签名覆盖当前文件全部内容"
            : "该签名之后存在其他签名或 PDF 增量更新"
        let trustNotice = signature.certificateTrustedBySystem
            ? "数字证书已通过 macOS 系统信任验证"
            : "数字证书未通过 macOS 系统信任验证"
        let validity = "\(formatted(signature.certificateNotBefore)) ～ \(formatted(signature.certificateNotAfter))"
        let appearance = signature.appearanceImagePNG.map {
            "<div class=\"signature-image-wrap\"><img class=\"signature-image\" alt=\"签名外观\" src=\"data:image/png;base64,\($0.base64EncodedString())\"></div>"
        } ?? "<div class=\"mini-stamp\">无图片签名</div>"
        return """
        <article class="card">
          <div class="card-head">
            <div class="card-title">#\(signature.index)　\(escape(signature.signerCommonName))</div>
            <div class="status"><span class="dot \(signature.protectedContentDigestMatches ? "ok" : "bad")">\(signature.protectedContentDigestMatches ? "✓" : "!")</span>\(integrityText)</div>
          </div>
          <div class="card-body">
            <div>
              <div class="section-title">签名信息</div>
              <div class="rows">
                <div class="label">签名时间：</div><div class="value">\(formatted(signature.signingTime))</div>
                <div class="label">时间来源：</div><div class="value">PDF 签名声明时间（非可信时间戳结论）</div>
                <div class="label">保护区 Hash：</div><div class="value hash">\(signature.protectedContentHashBase64)</div>
                <div class="label">签名类型：</div><div class="value">\(escape(signature.subFilter))</div>
                <div class="label">签名域：</div><div class="value hash">\(escape(signature.fieldName))</div>
              </div>
              <div class="section-title" style="margin-top:24px">证书信息</div>
              <div class="rows">
                <div class="label">序列号：</div><div class="value hash">\(escape(signature.certificateSerialNumber))</div>
                <div class="label">颁发机构：</div><div class="value">\(escape(signature.certificateIssuerCommonName))</div>
                <div class="label">证书组织：</div><div class="value">\(escape(signature.signerOrganization)) / \(escape(signature.signerOrganizationalUnit))</div>
                <div class="label">有效期：</div><div class="value">\(validity)</div>
              </div>
            </div>
            <aside>
              <div class="notice \(integrityClass)"><span class="notice-mark">\(signature.protectedContentDigestMatches ? "✓" : "!")</span><span>\(integrityText)</span></div>
              <div class="notice neutral"><span class="notice-mark">i</span><span>\(coverageNotice)</span></div>
              <div class="notice warn"><span class="notice-mark">!</span><span>\(trustNotice)</span></div>
              <div class="notice warn"><span class="notice-mark">!</span><span>\(certExpired ? "证书当前已过期；需结合签署时状态判断" : "证书当前仍在有效期内")</span></div>
              \(appearance)
            </aside>
          </div>
        </article>
        """
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func formatted(_ date: Date?) -> String {
        date.map(dateFormatter.string) ?? "未知"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
