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
                NotificationCenter.default.post(name: .sevenZipMacOpenURLs, object: urls)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if hasFinishedLaunching {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sevenZipMacOpenURLs, object: urls)
            }
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
