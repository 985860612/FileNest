import AppKit
import SwiftUI

@MainActor
final class FinderOperationWindowController: NSObject, NSWindowDelegate {
    static let shared = FinderOperationWindowController()

    private var windows: [UUID: NSWindow] = [:]
    private var models: [UUID: FinderOperationModel] = [:]

    func present(_ request: FinderActionRequest) {
        let id = UUID()
        let model = FinderOperationModel(request: request)
        let size = request.action == .browse
            ? NSSize(width: 780, height: 560)
            : NSSize(width: 640, height: 680)
        let rootView = FinderOperationView(model: model) { [weak self] in
            self?.closeWindow(id: id)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = request.action.title
        window.minSize = request.action == .browse
            ? NSSize(width: 680, height: 460)
            : NSSize(width: 560, height: 580)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        windows[id] = window
        models[id] = model
        NSApp.windows
            .filter { $0 !== window && $0.title == "SevenZip Mac" }
            .forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        guard let id = windows.first(where: { $0.value === closingWindow })?.key else { return }
        windows[id] = nil
        models[id] = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let id = windows.first(where: { $0.value === sender })?.key,
              let model = models[id], model.isWorking else { return true }
        model.cancel()
        return false
    }

    private func closeWindow(id: UUID) {
        windows[id]?.close()
        windows[id] = nil
        models[id] = nil
    }
}
