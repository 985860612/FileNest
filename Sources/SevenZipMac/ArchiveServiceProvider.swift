import AppKit
import Foundation

@objc final class ArchiveServiceProvider: NSObject {
    @objc func extractToNamedFolder(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let urls = fileURLs(from: pasteboard),
              !urls.isEmpty,
              urls.allSatisfy(ArchiveUtilities.looksLikeArchive) else {
            error.pointee = "请选择受支持的压缩文件" as NSString
            return
        }
        present(FinderActionRequest(action: .extract, urls: urls))
    }

    @objc func compressAsSevenZip(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        presentCompression(pasteboard, format: .sevenZip, error: error)
    }

    @objc func compressAsZip(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        presentCompression(pasteboard, format: .zip, error: error)
    }

    @objc func browseArchive(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let urls = fileURLs(from: pasteboard), urls.count == 1,
              let archive = urls.first, ArchiveUtilities.looksLikeArchive(archive) else {
            error.pointee = "请选择一个受支持的压缩文件" as NSString
            return
        }
        present(FinderActionRequest(action: .browse, urls: [archive]))
    }

    private func presentCompression(
        _ pasteboard: NSPasteboard,
        format: ArchiveFormat,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let urls = fileURLs(from: pasteboard), !urls.isEmpty else {
            error.pointee = "请选择要压缩的文件或文件夹" as NSString
            return
        }
        present(FinderActionRequest(action: .compress(format), urls: urls))
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        guard let paths = pasteboard.propertyList(forType: filenamesType) as? [String] else {
            return nil
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    private func present(_ request: FinderActionRequest) {
        Task { @MainActor in
            FinderOperationWindowController.shared.present(request)
        }
    }
}
