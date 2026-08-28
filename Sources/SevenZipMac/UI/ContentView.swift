import AppKit
import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case extract
    case compress
    case exportCatalog
    case copyFiles
    case trashFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extract: "解压缩"
        case .compress: "创建归档"
        case .exportCatalog: "导出文件目录"
        case .copyFiles: "批量复制文件"
        case .trashFiles: "移到废纸篓"
        }
    }

    var subtitle: String {
        switch self {
        case .extract: "打开 7z、ZIP、RAR 及更多归档格式"
        case .compress: "创建加密归档、调整字典并按大小分卷"
        case .exportCatalog: "扫描文件夹并生成 XLSX 目录清单"
        case .copyFiles: "按 Excel 中的源路径和目标路径复制文件"
        case .trashFiles: "按 Excel 路径预览并安全移除文件"
        }
    }

    var systemImage: String {
        switch self {
        case .extract: "archivebox"
        case .compress: "archivebox.fill"
        case .exportCatalog: "tablecells"
        case .copyFiles: "doc.on.doc"
        case .trashFiles: "trash"
        }
    }

    var fileManagementMode: FileManagementMode? {
        switch self {
        case .exportCatalog: .export
        case .copyFiles: .copy
        case .trashFiles: .trash
        default: nil
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel
    @StateObject private var fileManagementModel = FileManagementWorkspaceModel()
    @State private var destination: AppDestination? = .extract
    @State private var dropTargeted = false

    private var selectedDestination: AppDestination { destination ?? .extract }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle("SevenZip Mac")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 640)
        .toolbar { toolbarContent }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear { synchronize(with: selectedDestination) }
        .onChange(of: destination) { newValue in
            if let newValue { synchronize(with: newValue) }
        }
        .onChange(of: model.mode) { mode in
            guard destination == .extract || destination == .compress else { return }
            destination = mode == .extract ? .extract : .compress
        }
    }

    private func synchronize(with destination: AppDestination) {
        switch destination {
        case .extract: model.mode = .extract
        case .compress: model.mode = .compress
        case .exportCatalog, .copyFiles, .trashFiles:
            if let mode = destination.fileManagementMode { fileManagementModel.mode = mode }
        }
    }

    private var sidebar: some View {
        List(selection: $destination) {
            Section("归档") {
                sidebarRow(.extract)
                sidebarRow(.compress)
            }
            Section("Excel 文件管理") {
                sidebarRow(.exportCatalog)
                sidebarRow(.copyFiles)
                sidebarRow(.trashFiles)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SevenZip Mac")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        .safeAreaInset(edge: .bottom) {
            Label("所有处理均在本机完成", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
        }
    }

    private func sidebarRow(_ item: AppDestination) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(Optional(item))
            .accessibilityHint(item.subtitle)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedDestination {
        case .extract, .compress:
            archiveWorkspace
        case .exportCatalog, .copyFiles, .trashFiles:
            FileManagementView(model: fileManagementModel, destination: selectedDestination)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if selectedDestination == .extract || selectedDestination == .compress {
                Button(action: model.chooseFiles) {
                    Label("添加文件", systemImage: "plus")
                }
                .disabled(model.isWorking)
                .help("添加文件或文件夹 (⌘O)")
                if !model.selectedURLs.isEmpty {
                    Button(action: model.clear) {
                        Label("清空", systemImage: "xmark.circle")
                    }
                    .disabled(model.isWorking)
                    .help("清空所选项目")
                }
            }
        }
    }

    private var archiveWorkspace: some View {
        VStack(spacing: 0) {
            TaskHeader(
                title: selectedDestination.title,
                subtitle: selectedDestination.subtitle,
                systemImage: selectedDestination.systemImage
            )
            Divider()
            HSplitView {
                fileSelectionPanel
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                archiveOptionsPanel
                    .frame(minWidth: 310, idealWidth: 330, maxWidth: 380, maxHeight: .infinity)
            }
            Divider()
            archiveStatusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var fileSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selectedURLs.isEmpty ? "文件与文件夹" : "已选择 \(model.selectedURLs.count) 项")
                    .font(.headline)
                Spacer()
                if !model.selectedURLs.isEmpty {
                    Button("添加…", action: model.chooseFiles)
                        .buttonStyle(.link)
                        .disabled(model.isWorking)
                }
            }
            if model.selectedURLs.isEmpty {
                archiveDropZone
            } else {
                selectedFilesList
            }
        }
        .padding(20)
    }

    private var archiveDropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: dropTargeted ? "arrow.down.circle.fill" : selectedDestination.systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 5) {
                Text(selectedDestination == .extract ? "将归档拖到这里" : "将文件或文件夹拖到这里")
                    .font(.title3.weight(.semibold))
                Text(selectedDestination == .extract
                     ? "支持 7z、ZIP、RAR、TAR、GZIP、XZ 等格式"
                     : "可同时选择多个项目，原始文件不会被修改")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(selectedDestination == .extract ? "选择归档…" : "选择文件…", action: model.chooseFiles)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var selectedFilesList: some View {
        List {
            ForEach(model.selectedURLs, id: \.self) { url in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        model.remove(url)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isWorking)
                    .accessibilityLabel("移除 \(url.lastPathComponent)")
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: model.selectedURLs + urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var archiveOptionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if selectedDestination == .compress {
                    settingsSection("归档") {
                        settingRow("格式") {
                            Picker("", selection: $model.format) {
                                ForEach(ArchiveFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 135)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("压缩等级")
                                Spacer()
                                Text("\(Int(model.compressionLevel))")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $model.compressionLevel, in: 0...9, step: 1)
                                .accessibilityLabel("压缩等级")
                        }
                        if model.format == .sevenZip {
                            settingRow("字典大小") {
                                Picker("", selection: $model.dictionarySize) {
                                    ForEach(CompressionDictionarySize.allCases) { size in
                                        Text(size.displayName).tag(size)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 135)
                            }
                        }
                    }
                    settingsSection("分卷") {
                        settingRow("分卷大小") {
                            Picker("", selection: $model.volumePreset) {
                                ForEach(ArchiveVolumePreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 135)
                        }
                        if model.volumePreset == .custom {
                            HStack {
                                TextField("大小", value: $model.customVolumeMegabytes, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                Text("MB")
                                    .foregroundStyle(.secondary)
                            }
                            if !(1...1_048_576).contains(model.customVolumeMegabytes) {
                                Label("请输入 1–1,048,576 MB", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                settingsSection("安全") {
                    SecureField(selectedDestination == .extract ? "归档密码（如需要）" : "密码（可选）", text: $model.password)
                        .textFieldStyle(.roundedBorder)
                    if selectedDestination == .compress, model.format == .tar, !model.password.isEmpty {
                        Label("TAR 不支持密码保护", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Finder 快速操作", systemImage: "cursorarrow.rays")
                        .font(.subheadline.weight(.medium))
                    Text("安装到“应用程序”后，可直接在 Finder 中解压或创建 7z / ZIP。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .disabled(model.isWorking)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private var archiveStatusBar: some View {
        VStack(spacing: 8) {
            if model.isWorking {
                if let fraction = model.progressFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusMessage)
                        .font(.callout)
                    if model.isWorking, !model.currentPath.isEmpty {
                        Text(model.currentPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if model.isWorking {
                    Button("取消", action: model.cancel)
                } else {
                    Button(model.actionTitle, action: model.start)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!model.canStart || (model.format == .tar && !model.password.isEmpty))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(.bar)
    }
}

struct TaskHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
}

struct MacEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .foregroundStyle(.secondary)
        .padding(30)
    }
}
