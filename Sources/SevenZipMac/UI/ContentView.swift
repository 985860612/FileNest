import SwiftUI
import UniformTypeIdentifiers

private enum ApplicationSection: String, CaseIterable, Identifiable {
    case archive = "压缩解压"
    case files = "Excel 文件管理"

    var id: String { rawValue }
}

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel
    @StateObject private var fileManagementModel = FileManagementWorkspaceModel()
    @State private var section: ApplicationSection = .archive
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if section == .archive {
                archiveWorkspace
            } else {
                FileManagementView(model: fileManagementModel)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
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
        HStack(spacing: 14) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("SevenZip Mac")
                    .font(.title2.weight(.semibold))
                Text("7-Zip SDK · 所有文件仅在本机处理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("功能", selection: $section) {
                ForEach(ApplicationSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .disabled(model.isWorking || fileManagementModel.isWorking)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var archiveWorkspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                selectionPanel
                optionsPanel
            }
            .padding(22)
            Divider()
            footer
        }
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件")
                    .font(.headline)
                Spacer()
                Button("添加", action: model.chooseFiles)
                if !model.selectedURLs.isEmpty {
                    Button("清空", action: model.clear)
                }
            }
            Group {
                if model.selectedURLs.isEmpty {
                    dropZone
                } else {
                    List {
                        ForEach(model.selectedURLs, id: \.self) { url in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    model.remove(url)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isWorking)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.inset)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.accept(urls: urls)
                return true
            } isTargeted: { dropTargeted = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: dropTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary)
            Text("拖放文件或文件夹")
                .font(.headline)
            Text("支持 7z、ZIP、RAR、TAR、GZIP、XZ 等格式")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("选择文件…", action: model.chooseFiles)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7])
                )
        }
    }

    private var optionsPanel: some View {
        Form {
            Section("模式") {
                Picker("模式", selection: $model.mode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("选项") {
                if model.mode == .compress {
                    Picker("格式", selection: $model.format) {
                        ForEach(ArchiveFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Slider(value: $model.compressionLevel, in: 0...9, step: 1) {
                        Text("压缩等级")
                    } minimumValueLabel: {
                        Text("快")
                    } maximumValueLabel: {
                        Text("小")
                    }
                    Text("压缩等级：\(Int(model.compressionLevel))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("字典大小", selection: $model.dictionarySize) {
                        ForEach(CompressionDictionarySize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .disabled(model.format != .sevenZip)
                    if model.format != .sevenZip {
                        Text("字典大小仅适用于 7z")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("分卷大小", selection: $model.volumePreset) {
                        ForEach(ArchiveVolumePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    if model.volumePreset == .custom {
                        HStack {
                            TextField("大小", value: $model.customVolumeMegabytes, format: .number)
                                .textFieldStyle(.roundedBorder)
                            Text("MB")
                                .foregroundStyle(.secondary)
                        }
                        if !(1...1_048_576).contains(model.customVolumeMegabytes) {
                            Text("请输入 1–1,048,576 MB")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                SecureField(model.mode == .extract ? "密码（如需要）" : "密码（可选）", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                if model.mode == .compress, model.format == .tar, !model.password.isEmpty {
                    Label("TAR 格式不支持密码", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("Finder 右键") {
                Label("解压到同名文件夹", systemImage: "folder.badge.plus")
                Label("压缩为 7z / ZIP", systemImage: "archivebox")
                Text("安装到“应用程序”后，可在 Finder 的“快速操作”或“服务”中使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .disabled(model.isWorking)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if model.isWorking {
                if let fraction = model.progressFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(model.currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("取消", action: model.cancel)
                }
            } else {
                HStack {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.actionTitle, action: model.start)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canStart || (model.format == .tar && !model.password.isEmpty))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}
