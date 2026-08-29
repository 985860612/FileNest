import AppKit
import Foundation

@MainActor
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

    @objc func exportFolderCatalog(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let urls = fileURLs(from: pasteboard), urls.count == 1,
              let directory = urls.first, isDirectory(directory) else {
            error.pointee = "请选择一个文件夹" as NSString
            return
        }

        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            error.pointee = "无法访问桌面目录" as NSString
            return
        }

        let destination = FileCatalogService.desktopExportURL(for: directory, desktop: desktop)
        prepareForAuxiliaryWindow()
        NSApp.hide(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try FileCatalogService.export(directory: directory, to: destination)
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "文件列表导出失败"
                    alert.informativeText = message
                    alert.runModal()
                }
            }
        }
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

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func present(_ request: FinderActionRequest) {
        prepareForAuxiliaryWindow()
        FinderOperationWindowController.shared.present(request)
    }

    private func prepareForAuxiliaryWindow() {
        AppDelegate.shared?.prepareForAuxiliaryWindow()
    }
}
