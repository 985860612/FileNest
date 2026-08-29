import AppKit

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
            DispatchQueue.main.async {
                self.routeOpenedURLs(urls)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if hasFinishedLaunching {
            DispatchQueue.main.async {
                self.routeOpenedURLs(urls)
            }
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
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
