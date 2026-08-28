import SwiftUI

struct FileManagementView: View {
    @ObservedObject var model: FileManagementWorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(20)
            Divider()
            preview
            Divider()
            footer
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("确认移到废纸篓", isPresented: $model.showsTrashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive, action: model.executeTrash)
        } message: {
            Text("将处理预览中的 \(model.operations.filter(\.state.isExecutable).count) 个文件。文件可以从废纸篓恢复。")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("操作", selection: $model.mode) {
                ForEach(FileManagementMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isWorking)

            switch model.mode {
            case .export:
                exportControls
            case .copy:
                workbookControls(copying: true)
            case .trash:
                workbookControls(copying: false)
            }
        }
    }

    private var exportControls: some View {
        HStack(spacing: 12) {
            pathLabel(model.directoryURL?.path ?? "尚未选择目录")
            Button("选择目录…", action: model.chooseDirectory)
            Toggle("包含子目录", isOn: $model.recursively)
                .toggleStyle(.checkbox)
            Button("导出 XLSX…", action: model.exportDirectory)
                .buttonStyle(.borderedProminent)
                .disabled(model.directoryURL == nil || model.isWorking)
        }
    }

    private func workbookControls(copying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                pathLabel(model.workbookURL?.path ?? "尚未选择 Excel 文件")
                Button("选择 XLSX…", action: model.chooseWorkbook)
            }
            HStack(spacing: 14) {
                if copying {
                    columnPicker("源文件列", selection: $model.sourceColumn)
                    columnPicker("目标文件列", selection: $model.destinationColumn)
                } else {
                    columnPicker("文件路径列", selection: $model.pathColumn)
                }
                Spacer()
                Button("预览操作", action: model.preview)
                    .disabled(model.sheet == nil || model.isWorking)
                if copying {
                    Button("执行复制", action: model.executeCopy)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.operations.isEmpty || model.isWorking)
                } else {
                    Button("移到废纸篓", role: .destructive, action: model.requestTrash)
                        .disabled(model.operations.isEmpty || model.isWorking)
                }
            }
        }
    }

    private func columnPicker(_ title: String, selection: Binding<XLSXColumn?>) -> some View {
        Picker(title, selection: selection) {
            Text("请选择").tag(nil as XLSXColumn?)
            ForEach(model.columns) { column in
                Text(column.title).tag(Optional(column))
            }
        }
        .frame(maxWidth: 240)
    }

    private func pathLabel(_ path: String) -> some View {
        Text(path)
            .font(.callout)
            .foregroundStyle(path.hasPrefix("尚未") ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var preview: some View {
        if model.mode == .export {
            Table(model.catalogEntries) {
                TableColumn("文件名") { entry in Text(entry.fileName) }
                TableColumn("扩展名") { entry in Text(entry.fileExtension) }.width(80)
                TableColumn("大小(KB)") { entry in Text(entry.sizeInKilobytes) }.width(90)
                TableColumn("完整路径") { entry in Text(entry.fullPath).lineLimit(1) }
            }
            .overlay { emptyOverlay(text: "导出后在这里显示扫描结果") }
        } else if model.mode == .copy {
            Table(model.operations) {
                TableColumn("源文件") { item in
                    Text(item.sourcePath).lineLimit(1)
                }
                TableColumn("目标文件") { item in
                    Text(item.destinationPath ?? "").lineLimit(1)
                }
                TableColumn("状态") { item in
                    Text(item.state.label)
                        .foregroundStyle(item.state == .success ? .green : .secondary)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 150)
            }
            .overlay { emptyOverlay(text: "选择 Excel、指定列，然后预览操作") }
        } else {
            Table(model.operations) {
                TableColumn("文件路径") { item in
                    Text(item.sourcePath).lineLimit(1)
                }
                TableColumn("状态") { item in
                    Text(item.state.label)
                        .foregroundStyle(item.state == .success ? .green : .secondary)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 150)
            }
            .overlay { emptyOverlay(text: "选择 Excel、指定列，然后预览操作") }
        }
    }

    @ViewBuilder
    private func emptyOverlay(text: String) -> some View {
        if (model.mode == .export ? model.catalogEntries.isEmpty : model.operations.isEmpty), !model.isWorking {
            VStack(spacing: 10) {
                Image(systemName: model.mode.systemImage)
                    .font(.system(size: 36, weight: .light))
                Text(text)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if model.isWorking {
                if let fraction = model.progressFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            HStack {
                Text(model.statusMessage)
                Spacer()
                Text(model.currentPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 440, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
