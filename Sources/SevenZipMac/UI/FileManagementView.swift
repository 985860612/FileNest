import SwiftUI

struct FileManagementView: View {
    @ObservedObject var model: FileManagementWorkspaceModel
    let destination: AppDestination

    var body: some View {
        VStack(spacing: 0) {
            TaskHeader(
                title: destination.title,
                subtitle: destination.subtitle,
                systemImage: destination.systemImage,
                tint: destination.tint
            )
            Divider()
            controls
                .padding(.leading, WorkspaceLayout.leadingInset)
                .padding(.trailing, WorkspaceLayout.trailingInset)
                .padding(.vertical, WorkspaceLayout.verticalInset)
            Divider()
            preview
            Divider()
            statusBar
        }
        .background(FileNestTheme.workspaceBackground)
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

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.mode {
            case .export:
                exportControls
            case .copy:
                workbookControls(copying: true)
            case .trash:
                workbookControls(copying: false)
            }
        }
        .padding(16)
        .background(FileNestTheme.panelBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(FileNestTheme.border)
        }
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("扫描来源")
                .font(.headline)
            HStack(spacing: 10) {
                sourcePath(
                    model.directoryURL?.path,
                    placeholder: "选择需要生成目录清单的文件夹",
                    systemImage: "folder"
                )
                Button("选择文件夹…", action: model.chooseDirectory)
                    .disabled(model.isWorking)
                    .fileNestFormControl()
            }
            HStack {
                Toggle("包含子文件夹", isOn: $model.recursively)
                    .toggleStyle(.checkbox)
                    .disabled(model.isWorking)
                Spacer()
                Button("导出 XLSX…", action: model.exportDirectory)
                    .buttonStyle(.borderedProminent)
                    .fileNestFormControl()
                    .disabled(model.directoryURL == nil || model.isWorking)
            }
        }
    }

    private func workbookControls(copying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Excel 数据源")
                .font(.headline)
            HStack(spacing: 10) {
                sourcePath(
                    model.workbookURL?.path,
                    placeholder: "选择包含文件路径的 XLSX 工作簿",
                    systemImage: "tablecells"
                )
                Button("选择 Excel…", action: model.chooseWorkbook)
                    .disabled(model.isWorking)
                    .fileNestFormControl()
            }
            HStack(alignment: .bottom, spacing: 14) {
                if copying {
                    columnPicker("源文件列", selection: $model.sourceColumn)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 7)
                    columnPicker("目标文件列", selection: $model.destinationColumn)
                } else {
                    columnPicker("文件路径列", selection: $model.pathColumn)
                }
                Spacer()
                Button("预览", action: model.preview)
                    .disabled(model.sheet == nil || model.isWorking)
                    .fileNestFormControl()
                if copying {
                    Button("复制文件", action: model.executeCopy)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.operations.isEmpty || model.isWorking)
                        .fileNestFormControl()
                } else {
                    Button("移到废纸篓", role: .destructive, action: model.requestTrash)
                        .disabled(model.operations.isEmpty || model.isWorking)
                        .fileNestFormControl()
                }
            }
        }
    }

    private func sourcePath(_ path: String?, placeholder: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(path == nil ? .tertiary : .secondary)
            Text(path ?? placeholder)
                .foregroundStyle(path == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: FileNestTheme.formControlHeight)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    private func columnPicker(_ title: String, selection: Binding<XLSXColumn?>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("请选择").tag(nil as XLSXColumn?)
                ForEach(model.columns) { column in
                    Text(column.title).tag(Optional(column))
                }
            }
            .labelsHidden()
            .frame(minWidth: 150)
            .fileNestFormControl()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if model.mode == .export {
            if model.catalogEntries.isEmpty, !model.isWorking {
                MacEmptyState(
                    title: "尚未导出目录",
                    message: "选择文件夹并导出后，扫描到的文件会显示在这里。",
                    systemImage: "tablecells"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.catalogEntries) {
                    TableColumn("文件名") { entry in
                        Label(entry.fileName, systemImage: entry.fileExtension.isEmpty ? "doc" : "doc.fill")
                            .lineLimit(1)
                    }
                    TableColumn("扩展名") { entry in Text(entry.fileExtension) }
                        .width(80)
                    TableColumn("大小") { entry in Text("\(entry.sizeInKilobytes) KB").monospacedDigit() }
                        .width(105)
                    TableColumn("完整路径") { entry in
                        Text(entry.fullPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        } else if model.mode == .copy {
            if model.operations.isEmpty, !model.isWorking {
                operationsEmptyState
            } else {
                Table(model.operations) {
                    TableColumn("源文件") { item in
                        Text(item.sourcePath).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("目标文件") { item in
                        Text(item.destinationPath ?? "").lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("状态") { item in operationState(item.state) }
                        .width(min: 110, ideal: 150)
                }
            }
        } else {
            if model.operations.isEmpty, !model.isWorking {
                operationsEmptyState
            } else {
                Table(model.operations) {
                    TableColumn("文件路径") { item in
                        Text(item.sourcePath).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("状态") { item in operationState(item.state) }
                        .width(min: 110, ideal: 150)
                }
            }
        }
    }

    @ViewBuilder
    private var operationsEmptyState: some View {
        if model.operations.isEmpty, !model.isWorking {
            MacEmptyState(
                title: "先预览，再执行",
                message: "选择 Excel 工作簿和对应表头列，应用会先检查每一条路径。",
                systemImage: model.mode.systemImage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func operationState(_ state: FileOperationState) -> some View {
        let appearance: (String, Color) = switch state {
        case .ready: ("circle", .secondary)
        case .success: ("checkmark.circle.fill", .green)
        case .missing, .invalid: ("exclamationmark.triangle.fill", .orange)
        case .failed: ("xmark.circle.fill", .red)
        }
        return Label(state.label, systemImage: appearance.0)
            .foregroundStyle(appearance.1)
            .lineLimit(1)
    }

    private var statusBar: some View {
        VStack(spacing: 7) {
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
                if !model.currentPath.isEmpty {
                    Text(model.currentPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 430, alignment: .trailing)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, 11)
        .frame(minHeight: FileNestTheme.statusBarHeight)
        .background(FileNestTheme.panelBackground)
    }
}
