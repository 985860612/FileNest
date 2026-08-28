import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ArchiveServiceProvider()
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSRegisterServicesProvider(serviceProvider, "SevenZipMac")
        if !pendingURLs.isEmpty {
            NotificationCenter.default.post(name: .sevenZipMacOpenURLs, object: pendingURLs)
            pendingURLs.removeAll()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if application.isRunning {
            NotificationCenter.default.post(name: .sevenZipMacOpenURLs, object: urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

