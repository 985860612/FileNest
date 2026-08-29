import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private let serviceProvider = ArchiveServiceProvider()
    private var pendingURLs: [URL] = []
    private var hasFinishedLaunching = false
    private var isResolvingInitialLaunch = true
    private var suppressInitialMainWindow = false

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.hide(nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyOrMain(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyOrMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSRegisterServicesProvider(serviceProvider, "SevenZipMac")
        hasFinishedLaunching = true
        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            routeOpenedURLs(urls)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.finishInitialLaunchRouting()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if hasFinishedLaunching {
            routeOpenedURLs(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isResolvingInitialLaunch
    }

    func prepareForAuxiliaryWindow() {
        if isResolvingInitialLaunch {
            suppressInitialMainWindow = true
        }
        hideMainWindow()
    }

    @objc private func windowDidBecomeKeyOrMain(_ notification: Notification) {
        guard isResolvingInitialLaunch,
              let window = notification.object as? NSWindow,
              window.title == "文件台" else { return }
        window.alphaValue = 0
        window.orderOut(nil)
    }

    private func finishInitialLaunchRouting() {
        guard isResolvingInitialLaunch else { return }
        isResolvingInitialLaunch = false
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        if suppressInitialMainWindow {
            hideMainWindow()
        } else if let mainWindow = NSApp.windows.first(where: { $0.title == "文件台" }) {
            mainWindow.alphaValue = 1
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.unhideWithoutActivation()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func hideMainWindow() {
        NSApp.windows
            .filter { $0.title == "文件台" }
            .forEach {
                $0.alphaValue = 0
                $0.orderOut(nil)
            }
    }

    private func routeOpenedURLs(_ urls: [URL]) {
        if urls.count == 1, let archive = urls.first, ArchiveUtilities.looksLikeArchive(archive) {
            prepareForAuxiliaryWindow()
            FinderOperationWindowController.shared.present(
                FinderActionRequest(action: .browse, urls: [archive])
            )
        } else {
            NotificationCenter.default.post(name: .sevenZipMacOpenURLs, object: urls)
        }
    }
}
