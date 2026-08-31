import SwiftUI

public struct FileNestApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = WorkspaceModel()

    public init() {}

    public var body: some Scene {
        Window("文件台", id: "main") {
            ContentView(model: model)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") { model.chooseFiles() }
                    .keyboardShortcut("o")
                Button("清空") { model.clear() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(model.selectedURLs.isEmpty || model.isWorking)
            }
        }

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("文件台 · FileNest")
                    .font(.title2.weight(.semibold))
                Text("进程内使用 7-Zip SDK 26.02，不调用命令行工具。")
                Text("RAR 仅支持解压，不支持创建。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}
