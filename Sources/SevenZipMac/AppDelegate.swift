import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ArchiveServiceProvider()
    private var pendingURLs: [URL] = []
    private var hasFinishedLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSRegisterServicesProvider(serviceProvider, "SevenZipMac")
        hasFinishedLaunching = true
        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            hideMainWindowIfOpeningArchive(urls)
            routeOpenedURLs(urls)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if hasFinishedLaunching {
            hideMainWindowIfOpeningArchive(urls)
            routeOpenedURLs(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func hideMainWindowIfOpeningArchive(_ urls: [URL]) {
        guard urls.count == 1,
              urls.first.map(ArchiveUtilities.looksLikeArchive) == true else { return }
        NSApp.windows
            .filter { $0.title == "文件台" }
            .forEach { $0.orderOut(nil) }
    }

    private func routeOpenedURLs(_ urls: [URL]) {
        if urls.count == 1, let archive = urls.first, ArchiveUtilities.looksLikeArchive(archive) {
            FinderOperationWindowController.shared.present(
                FinderActionRequest(action: .browse, urls: [archive])
            )
        } else {
            NotificationCenter.default.post(name: .sevenZipMacOpenURLs, object: urls)
        }
    }
}
