import AppKit
import FileNestOCRCore
import SwiftUI

enum WorkspaceLayout {
    static let leadingInset: CGFloat = 17
    static let trailingInset: CGFloat = 20
    static let verticalInset: CGFloat = 20
}

enum AppDestination: String, CaseIterable, Identifiable {
    case extract
    case compress
    case exportCatalog
    case copyFiles
    case renameFiles
    case trashFiles
    case fileTools
    case imageTools
    case pdfTools
    case spreadsheetTools
    case textRecognition
    case documentRecognition
    case hashVerification
    case ncmConversion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extract: "解压缩"
        case .compress: "创建归档"
        case .exportCatalog: "导出文件目录"
        case .copyFiles: "批量复制文件"
        case .renameFiles: "批量重命名文件"
        case .trashFiles: "移到废纸篓"
        case .fileTools: "文件整理"
        case .imageTools: "图片处理"
        case .pdfTools: "PDF 工具"
        case .spreadsheetTools: "Excel 分组合并"
        case .textRecognition: "文字识别 OCR"
        case .documentRecognition: "文档识别"
        case .hashVerification: "Hash 校验"
        case .ncmConversion: "NCM 转换"
        }
    }

    var subtitle: String {
        switch self {
        case .extract: "打开 7z、ZIP、RAR 及更多归档格式"
        case .compress: "创建加密归档、调整字典并按大小分卷"
        case .exportCatalog: "扫描文件夹并生成 XLSX 目录清单"
        case .copyFiles: "按 Excel 中的源路径和目标路径复制文件"
        case .renameFiles: "按 Excel 中的文件路径和新文件名批量重命名"
        case .trashFiles: "按 Excel 路径预览并安全移除文件"
        case .fileTools: "扩展名修复、正则复制与名称清理"
        case .imageTools: "批量压缩、缩放和格式转换"
        case .pdfTools: "图片转 PDF、排序合并、拆分与提取"
        case .spreadsheetTools: "按指定列分组并合并其他列"
        case .textRecognition: "只运行 PP-OCRv5 文字检测与识别"
        case .documentRecognition: "原生 PP-StructureV3 批量识别与结构化导出"
        case .hashVerification: "计算并验证文件的 MD5、SHA-1、SHA-256 或 SHA-512"
        case .ncmConversion: "在本机恢复 NCM 中的原始 MP3 或 FLAC 音频"
        }
    }

    var systemImage: String {
        switch self {
        case .extract: "tray.and.arrow.down.fill"
        case .compress: "tray.and.arrow.up.fill"
        case .exportCatalog: "tablecells.fill"
        case .copyFiles: "doc.on.doc.fill"
        case .renameFiles: "pencil"
        case .trashFiles: "trash.fill"
        case .fileTools: "wand.and.stars"
        case .imageTools: "photo.on.rectangle.angled"
        case .pdfTools: "doc.richtext.fill"
        case .spreadsheetTools: "rectangle.3.group.fill"
        case .textRecognition: "text.viewfinder"
        case .documentRecognition: "doc.text.magnifyingglass"
        case .hashVerification: "checkmark.shield.fill"
        case .ncmConversion: "music.note.list"
        }
    }

    var tint: Color {
        switch self {
        case .extract, .compress: FileNestTheme.accent
        case .exportCatalog: FileNestTheme.green
        case .copyFiles: FileNestTheme.teal
        case .renameFiles: FileNestTheme.orange
        case .trashFiles: FileNestTheme.red
        case .fileTools: FileNestTheme.teal
        case .imageTools: FileNestTheme.orange
        case .pdfTools: FileNestTheme.violet
        case .spreadsheetTools: FileNestTheme.green
        case .textRecognition, .documentRecognition: FileNestTheme.teal
        case .hashVerification: FileNestTheme.violet
        case .ncmConversion: FileNestTheme.orange
        }
    }

    var fileManagementMode: FileManagementMode? {
        switch self {
        case .exportCatalog: .export
        case .copyFiles: .copy
        case .renameFiles: .rename
        case .trashFiles: .trash
        default: nil
        }
    }
}

struct ContentView: View {
    private static let sidebarWidth: CGFloat = 220

    @ObservedObject var model: WorkspaceModel
    @StateObject private var fileManagementModel = FileManagementWorkspaceModel()
    @StateObject private var hashModel = HashWorkspaceModel()
    @StateObject private var ncmModel = NCMWorkspaceModel()
    @StateObject private var fileToolsModel = FileToolsWorkspaceModel()
    @StateObject private var imageToolsModel = ImageToolsWorkspaceModel()
    @StateObject private var pdfToolsModel = PDFToolsWorkspaceModel()
    @StateObject private var spreadsheetToolsModel = SpreadsheetToolsWorkspaceModel()
    @StateObject private var textRecognitionModel = DocumentRecognitionWorkspaceModel(mode: .ocr)
    @StateObject private var documentRecognitionModel = DocumentRecognitionWorkspaceModel()
    @State private var destination: AppDestination? = .extract
    @State private var dropTargeted = false
    @State private var isSidebarVisible = true

    private var selectedDestination: AppDestination { destination ?? .extract }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                sidebar
                    .frame(width: Self.sidebarWidth)
                    .offset(x: isSidebarVisible ? 0 : -12)
            }
            .frame(width: isSidebarVisible ? Self.sidebarWidth : 0)
            .opacity(isSidebarVisible ? 1 : 0)
            .clipped()
            .accessibilityHidden(!isSidebarVisible)

            Divider()
                .opacity(isSidebarVisible ? 1 : 0)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: isSidebarVisible)
        .tint(FileNestTheme.accent)
        .frame(minWidth: 900, minHeight: 580)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar { toolbarContent }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("需要归档密码", isPresented: $model.showsPasswordPrompt) {
            SecureField("归档密码", text: $model.password)
            Button("取消", role: .cancel, action: model.cancelArchivePassword)
            Button("继续", action: model.submitArchivePassword)
                .disabled(model.password.isEmpty)
        } message: {
            Text(model.passwordPromptMessage)
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
        case .extract:
            model.mode = .extract
            model.refreshArchiveContents()
        case .compress: model.mode = .compress
        case .exportCatalog, .copyFiles, .renameFiles, .trashFiles:
            if let mode = destination.fileManagementMode { fileManagementModel.mode = mode }
        case .fileTools, .imageTools, .pdfTools, .spreadsheetTools, .textRecognition, .documentRecognition:
            break
        case .hashVerification:
            break
        case .ncmConversion:
            break
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarSection("归档", items: [.extract, .compress])
                    sidebarSection("Excel 文件管理", items: [.exportCatalog, .copyFiles, .renameFiles, .trashFiles])
                    sidebarSection("文件与文档", items: [.fileTools, .imageTools, .pdfTools, .spreadsheetTools, .textRecognition, .documentRecognition])
                    sidebarSection("工具", items: [.hashVerification, .ncmConversion])
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
            }
            Divider()
            Label("所有处理均在本机完成", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: FileNestTheme.statusBarHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FileNestTheme.panelBackground)
        }
        .background(FileNestTheme.sidebarBackground)
    }

    private func sidebarSection(_ title: String, items: [AppDestination]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 9)
            ForEach(items) { item in
                sidebarRow(item)
            }
        }
    }

    private func sidebarRow(_ item: AppDestination) -> some View {
        let selected = selectedDestination == item
        return Button {
            destination = item
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(item.tint.opacity(selected ? 0.25 : 0.14))
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(item.tint)
                }
                .frame(width: 27, height: 27)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background(
                selected ? item.tint.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.subtitle)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedDestination {
        case .extract, .compress:
            archiveWorkspace
        case .exportCatalog, .copyFiles, .renameFiles, .trashFiles:
            FileManagementView(model: fileManagementModel, destination: selectedDestination)
        case .fileTools:
            FileToolsView(model: fileToolsModel)
        case .imageTools:
            ImageToolsView(model: imageToolsModel)
        case .pdfTools:
            PDFToolsView(model: pdfToolsModel)
        case .spreadsheetTools:
            SpreadsheetToolsView(model: spreadsheetToolsModel)
        case .textRecognition:
            DocumentRecognitionView(model: textRecognitionModel)
        case .documentRecognition:
            DocumentRecognitionView(model: documentRecognitionModel)
        case .hashVerification:
            HashToolView(model: hashModel)
        case .ncmConversion:
            NCMConverterView(model: ncmModel)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isSidebarVisible.toggle()
            } label: {
                Label(isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏", systemImage: "sidebar.left")
            }
            .help(isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏")
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
            } else if selectedDestination == .hashVerification {
                Button(action: hashModel.chooseFiles) {
                    Label("添加文件", systemImage: "plus")
                }
                .disabled(hashModel.isWorking)
                .help("添加要计算 Hash 的文件")
                if !hashModel.selectedURLs.isEmpty {
                    Button(action: hashModel.clear) {
                        Label("清空", systemImage: "xmark.circle")
                    }
                    .disabled(hashModel.isWorking)
                    .help("清空文件和结果")
                }
            } else if selectedDestination == .ncmConversion {
                Button(action: ncmModel.chooseFiles) {
                    Label("添加 NCM", systemImage: "plus")
                }
                .disabled(ncmModel.isWorking)
                .help("添加 NCM 文件或文件夹")
                if !ncmModel.items.isEmpty {
                    Button(action: ncmModel.clear) {
                        Label("清空", systemImage: "xmark.circle")
                    }
                    .disabled(ncmModel.isWorking)
                    .help("清空文件和转换结果")
                }
            }
        }
    }

    private var archiveWorkspace: some View {
        VStack(spacing: 0) {
            TaskHeader(
                title: selectedDestination.title,
                subtitle: selectedDestination.subtitle,
                systemImage: selectedDestination.systemImage,
                tint: selectedDestination.tint
            )
            Divider()
            HStack(spacing: 0) {
                fileSelectionPanel
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                if selectedDestination == .compress {
                    Divider()
                    archiveOptionsPanel
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                }
            }
            Divider()
            archiveStatusBar
        }
        .background(FileNestTheme.workspaceBackground)
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
            } else if selectedDestination == .extract,
                      model.selectedURLs.count == 1,
                      model.selectedURLs.first.map(ArchiveUtilities.looksLikeArchive) == true {
                archiveContentsPreview
            } else {
                selectedFilesList
            }
        }
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, WorkspaceLayout.verticalInset)
    }

    private var archiveDropZone: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selectedDestination.tint.opacity(0.13))
                Image(systemName: dropTargeted ? "arrow.down" : selectedDestination.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(selectedDestination.tint)
                    .symbolRenderingMode(.monochrome)
            }
            .frame(width: 68, height: 68)
            .scaleEffect(dropTargeted ? 1.06 : 1)
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
        .background(dropTargeted ? selectedDestination.tint.opacity(0.10) : FileNestTheme.recessedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    dropTargeted ? selectedDestination.tint : FileNestTheme.border,
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

    private var archiveContentsPreview: some View {
        VStack(spacing: 0) {
            if let archive = model.selectedURLs.first {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: archive.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(archive.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(model.isLoadingArchiveContents
                             ? "正在读取目录…"
                             : "\(model.archiveEntries.count) 个项目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: model.refreshArchiveContents) {
                        Label("重新读取", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(model.isLoadingArchiveContents || model.isWorking)
                    .help("重新读取归档内容")
                }
                .padding(12)
            }
            Divider()
            if model.isLoadingArchiveContents {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在读取归档中的文件…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.archivePreviewError {
                MacEmptyState(
                    title: "无法读取归档内容",
                    message: message,
                    systemImage: "lock.trianglebadge.exclamationmark",
                    actionTitle: "重新读取",
                    action: model.refreshArchiveContents
                )
            } else if model.archiveEntries.isEmpty {
                MacEmptyState(
                    title: "归档为空",
                    message: "这个归档中没有可显示的文件。",
                    systemImage: "archivebox"
                )
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button(action: model.browseArchiveUp) {
                            Label("上一级", systemImage: "chevron.left")
                        }
                        .disabled(!model.canBrowseArchiveUp)
                        Text(model.archiveBrowserTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("当前层级 \(model.archiveBrowserItems.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    Divider()
                    Table(model.archiveBrowserItems) {
                        TableColumn("名称") { item in
                            if item.directory {
                                Button {
                                    model.openArchiveBrowserItem(item)
                                } label: {
                                    HStack {
                                        Label(item.name, systemImage: "folder")
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Label(item.name, systemImage: "doc")
                                    .lineLimit(1)
                            }
                        }
                        TableColumn("类型") { item in
                            Text(item.directory ? "文件夹" : "文件")
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 80, ideal: 100)
                        TableColumn("大小") { item in
                            Text(item.formattedSize)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .width(min: 72, ideal: 90)
                    }
                }
            }
        }
        .background(FileNestTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: urls)
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
                            .fileNestFormControl()
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
                                .fileNestFormControl()
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
                            .fileNestFormControl()
                        }
                        if model.volumePreset == .custom {
                            HStack {
                                TextField("大小", value: $model.customVolumeMegabytes, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .fileNestFormControl()
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
                    settingsSection("文件") {
                        Toggle("排除 macOS 元数据", isOn: $model.excludeMacOSMetadata)
                            .help("排除 .DS_Store、._*、__MACOSX 等系统生成文件")
                        Text("普通点文件（如 .gitignore）仍会保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                settingsSection("安全") {
                    SecureField("密码（可选）", text: $model.password)
                        .textFieldStyle(.roundedBorder)
                        .fileNestFormControl()
                    if model.format == .tar, !model.password.isEmpty {
                        Label("TAR 不支持密码保护", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(16)
        }
        .background(FileNestTheme.workspaceBackground)
        .disabled(model.isWorking)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: settingsSectionIcon(title))
                    .foregroundStyle(FileNestTheme.accent)
                Text(title)
                    .foregroundStyle(.primary)
            }
            .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(FileNestTheme.panelBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(FileNestTheme.border)
        }
    }

    private func settingsSectionIcon(_ title: String) -> String {
        switch title {
        case "归档": "archivebox.fill"
        case "分卷": "square.stack.3d.up.fill"
        case "文件": "doc.fill"
        case "安全": "lock.shield.fill"
        default: "gearshape.fill"
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
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, 5)
        .frame(minHeight: FileNestTheme.statusBarHeight)
        .background(FileNestTheme.panelBackground)
    }
}

private extension ArchiveBrowserItem {
    var formattedSize: String {
        guard !directory else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)
    }
}

struct TaskHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, 15)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MacEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

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
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.secondary)
        .padding(30)
    }
}
