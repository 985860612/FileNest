import AppKit
import Foundation

@objc final class ArchiveServiceProvider: NSObject {
    private let engine = ArchiveEngine.shared

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
        let engine = engine
        runServiceJob {
            var outputs: [URL] = []
            for archive in urls {
                let destination = ArchiveUtilities.extractionFolder(for: archive)
                try engine.extract(
                    archive: archive,
                    to: destination,
                    password: "",
                    cancellation: ArchiveCancellation(),
                    progress: { _ in }
                )
                outputs.append(destination)
            }
            return outputs
        }
    }

    @objc func compressAsSevenZip(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        compress(pasteboard, format: .sevenZip, error: error)
    }

    @objc func compressAsZip(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        compress(pasteboard, format: .zip, error: error)
    }

    private func compress(
        _ pasteboard: NSPasteboard,
        format: ArchiveFormat,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let urls = fileURLs(from: pasteboard), !urls.isEmpty else {
            error.pointee = "请选择要压缩的文件或文件夹" as NSString
            return
        }
        let engine = engine
        runServiceJob {
            let destination = ArchiveUtilities.archiveDestination(for: urls, format: format)
            try engine.compress(
                inputs: urls,
                to: destination,
                format: format,
                password: "",
                level: 5,
                cancellation: ArchiveCancellation(),
                progress: { _ in }
            )
            return [destination]
        }
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }

    private func runServiceJob(_ work: @escaping @Sendable () throws -> [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outputs = try work()
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "SevenZip Mac 操作失败"
                    alert.informativeText = message
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}
