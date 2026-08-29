import AppKit
import SwiftUI

struct FinderOperationView: View {
    @ObservedObject var model: FinderOperationModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isBrowseOnly {
                browserContent
            } else {
                operationContent
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: model.action.systemImage)
                .font(.system(size: 27, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.action.title)
                    .font(.title2.weight(.semibold))
                Text(model.action.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var operationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inputSection
                if model.isCompression {
                    compressionSettings
                } else {
                    extractionSettings
                    archivePreview
                }
            }
            .padding(20)
        }
        .disabled(model.isWorking)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(model.isCompression ? "待压缩项目" : "归档")
            VStack(spacing: 0) {
                ForEach(model.selectedURLs, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    if url != model.selectedURLs.last { Divider().padding(.leading, 47) }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color(nsColor: .separatorColor)) }
            .frame(maxHeight: 150)
        }
    }

    private var compressionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("压缩设置")
            settingRow("格式") {
                Picker("", selection: Binding(
                    get: { model.format },
                    set: { newFormat in
                        model.setFormat(newFormat)
                    }
                )) {
                    ForEach(ArchiveFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            destinationRow
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("压缩等级")
                    Spacer()
                    Text("\(Int(model.compressionLevel))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $model.compressionLevel, in: 0...9, step: 1)
            }
            if model.format == .sevenZip {
                settingRow("字典大小") {
                    Picker("", selection: $model.dictionarySize) {
                        ForEach(CompressionDictionarySize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            settingRow("分卷大小") {
                Picker("", selection: $model.volumePreset) {
                    ForEach(ArchiveVolumePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            if model.volumePreset == .custom {
                HStack {
                    Text("自定义分卷")
                    Spacer()
                    TextField("大小", value: $model.customVolumeMegabytes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 105)
                    Text("MB").foregroundStyle(.secondary)
                }
            }
            SecureField("密码（可选）", text: $model.password)
                .textFieldStyle(.roundedBorder)
            if model.format == .tar, !model.password.isEmpty {
                Label("TAR 不支持密码保护", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle("排除 macOS 元数据", isOn: $model.excludeMacOSMetadata)
                .help("排除 .DS_Store、._*、__MACOSX 等系统生成文件")
        }
    }

    private var extractionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("解压设置")
            destinationRow
            HStack(spacing: 8) {
                SecureField("归档密码（如需要）", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.loadContents)
                Button("读取目录", action: model.loadContents)
            }
        }
    }

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.isCompression ? "输出文件" : "输出位置")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                Text(model.destinationURL.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)) }
                Button("选择…", action: model.chooseDestination)
            }
        }
    }

    private var archivePreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionTitle("归档内容")
                Spacer()
                if !model.entries.isEmpty {
                    Text("\(model.entries.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if model.isLoadingContents {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .frame(height: 100)
            } else if model.entries.isEmpty {
                Text("输入密码后可读取并预览归档目录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                Table(model.entries) {
                    TableColumn("名称") { entry in
                        Label(entry.path, systemImage: entry.directory ? "folder" : "doc")
                            .lineLimit(1)
                    }
                    TableColumn("大小") { entry in sizeText(entry) }
                        .width(90)
                }
                .frame(height: 150)
            }
        }
    }

    private var browserContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("搜索归档中的文件", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                SecureField("密码（如需要）", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .onSubmit(model.loadContents)
                Button(action: model.loadContents) {
                    Label("重新读取", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingContents)
            }
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: model.selectedURLs[0].path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedURLs[0].lastPathComponent).font(.headline)
                    Text(model.selectedURLs[0].path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(model.filteredEntries.count) 项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.isLoadingContents {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取归档目录…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.filteredEntries) {
                    TableColumn("路径") { entry in
                        Label(entry.path, systemImage: entry.directory ? "folder" : "doc")
                            .lineLimit(1)
                    }
                    TableColumn("类型") { entry in
                        Text(entry.directory ? "文件夹" : "文件").foregroundStyle(.secondary)
                    }
                    .width(82)
                    TableColumn("大小") { entry in sizeText(entry) }
                        .width(100)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if model.isWorking {
                if let progress = model.progressFraction {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusMessage).font(.callout)
                    if !model.currentPath.isEmpty {
                        Text(model.currentPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if !model.resultURLs.isEmpty {
                    Button("在 Finder 中显示", action: model.revealResults)
                }
                if model.isWorking {
                    Button("取消", action: model.cancel)
                } else if !model.isBrowseOnly {
                    Button(model.actionTitle, action: model.start)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!model.canStart)
                }
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private func sizeText(_ entry: ArchiveEntry) -> some View {
        Text(entry.directory ? "—" : ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.size), countStyle: .file))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}
