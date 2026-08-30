import SwiftUI

struct FileToolsView: View {
    @ObservedObject var model: FileToolsWorkspaceModel

    var body: some View {
        ToolPage(title: "文件整理", subtitle: "扩展名修复、正则复制与安全名称清理", icon: "wand.and.stars", status: model.statusMessage) {
            Picker("处理方式", selection: $model.mode) {
                ForEach(FileToolMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            ToolDirectoryRow(label: "来源目录", url: model.rootURL, action: model.chooseRoot)
            if model.mode == .regexCopy {
                ToolDirectoryRow(label: "输出目录", url: model.outputURL, action: model.chooseOutput)
                HStack {
                    TextField("正则表达式", text: $model.regexPattern)
                    TextField("替换模板，例如 分类/$1", text: $model.replacement)
                }
            }
            HStack {
                Text(model.mode == .extensionRepair
                     ? "仅修复无扩展名且能由文件签名可靠识别的文件。"
                     : model.mode == .sanitizeNames
                     ? "保留中文、字母、数字、连字符和下划线；执行前会检查冲突。"
                     : "正则作用于来源目录内的相对路径，输出不能逃逸目标目录。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("生成预览", action: model.preview).disabled(model.isWorking || model.rootURL == nil)
                Button("执行", action: model.requestExecution)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking || !model.operations.contains(where: \.state.isExecutable))
            }
        } content: {
            Table(model.operations) {
                TableColumn("来源") { Text($0.source.path).lineLimit(1).truncationMode(.middle) }
                TableColumn("目标") { Text($0.destination.path).lineLimit(1).truncationMode(.middle) }
                TableColumn("状态") { Text($0.state.label).lineLimit(1) }.width(120)
            }
        }
        .alert("确认执行", isPresented: $model.showsExecutionConfirmation) {
            Button("取消", role: .cancel) {}
            Button(model.mode == .regexCopy ? "复制" : "重命名", action: model.execute)
        } message: {
            Text("将执行 \(model.operations.filter(\.state.isExecutable).count) 项操作，请先核对预览。")
        }
        .toolErrorAlert($model.errorMessage)
    }
}

struct ImageToolsView: View {
    @ObservedObject var model: ImageToolsWorkspaceModel

    var body: some View {
        ToolPage(title: "图片处理", subtitle: "批量压缩、按比例缩放并转换格式", icon: "photo.on.rectangle.angled", status: model.statusMessage) {
            ToolDirectoryRow(label: "图片目录", url: model.rootURL, action: model.chooseRoot)
            ToolDirectoryRow(label: "输出目录（可选）", url: model.outputURL, action: model.chooseOutput)
            HStack(spacing: 14) {
                TextField("最大宽度", text: $model.maximumWidth).frame(width: 110)
                TextField("最大高度", text: $model.maximumHeight).frame(width: 110)
                Picker("输出格式", selection: $model.format) {
                    ForEach(ImageOutputFormat.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 180)
                Text("质量 \(Int(model.quality * 100))").monospacedDigit().frame(width: 70)
                Slider(value: $model.quality, in: 0.2...1).frame(maxWidth: 180)
            }
            HStack {
                Toggle("包含子目录", isOn: $model.recursively).toggleStyle(.checkbox)
                Toggle("替换原图", isOn: $model.replaceOriginals).toggleStyle(.checkbox)
                Spacer()
                Button("开始处理", action: model.requestRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.rootURL == nil || model.isWorking)
            }
        } content: {
            Table(model.results) {
                TableColumn("来源") { Text($0.source.path).lineLimit(1).truncationMode(.middle) }
                TableColumn("输出") { Text($0.destination.path).lineLimit(1).truncationMode(.middle) }
                TableColumn("结果") { Text($0.error ?? "成功").lineLimit(1) }.width(min: 100, ideal: 180)
            }
        }
        .alert("确认替换原图", isPresented: $model.showsReplaceConfirmation) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive, action: model.run)
        } message: { Text("成功写入新图片后会移除对应原文件，此操作不可从应用内撤销。") }
        .toolErrorAlert($model.errorMessage)
    }
}

struct PDFToolsView: View {
    @ObservedObject var model: PDFToolsWorkspaceModel

    var body: some View {
        ToolPage(title: "PDF 工具", subtitle: "图片转换、目录合并、关键字拆分与正则提取", icon: "doc.richtext", status: model.statusMessage) {
            Picker("处理方式", selection: $model.mode) {
                ForEach(PDFToolMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            ToolDirectoryRow(label: "来源目录", url: model.rootURL, action: model.chooseRoot)
            if model.mode != .regex {
                ToolDirectoryRow(label: "输出目录（可选）", url: model.outputURL, action: model.chooseOutput)
            }
            switch model.mode {
            case .imagesToPDF:
                Toggle("包含子目录", isOn: $model.recursively).toggleStyle(.checkbox)
            case .merge:
                TextField("排序规则，每行“关键字:优先级”，例如 判决书:10", text: $model.sortConfiguration, axis: .vertical)
                    .lineLimit(2...5)
                Text("每个一级子目录生成一个同名 PDF；支持 PDF、JPEG、PNG、HEIC、TIFF 和 BMP。")
                    .font(.caption).foregroundStyle(.secondary)
            case .split:
                HStack {
                    TextField("每次出现该关键字时开始一个新 PDF", text: $model.keyword)
                    Toggle("包含子目录", isOn: $model.recursively).toggleStyle(.checkbox)
                }
            case .regex:
                HStack {
                    TextField("正则表达式；有捕获组时导出第一个捕获组", text: $model.regexPattern)
                    Toggle("包含子目录", isOn: $model.recursively).toggleStyle(.checkbox)
                }
            }
            HStack {
                Text("仅文字型 PDF 可用于关键字拆分和正则提取。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.mode == .merge {
                    Button("排序预览", action: model.previewMerge)
                        .disabled(model.rootURL == nil || model.isWorking)
                }
                Button(model.mode == .regex ? "提取并导出 XLSX…" : "开始处理", action: model.run)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.rootURL == nil || model.isWorking)
            }
        } content: {
            if model.mode == .regex {
                Table(model.extractedRows) {
                    TableColumn("文件") { Text($0.fileName).lineLimit(1) }
                    TableColumn("提取内容") { Text($0.value).lineLimit(1) }
                    TableColumn("路径") { Text($0.filePath).lineLimit(1).truncationMode(.middle) }
                }
            } else if model.mode == .merge, !model.mergePreview.isEmpty, model.results.isEmpty {
                Table(model.mergePreview) {
                    TableColumn("目录") { Text($0.directory.lastPathComponent).lineLimit(1) }
                    TableColumn("顺序") { Text("\($0.order)").monospacedDigit() }.width(55)
                    TableColumn("文件") { Text($0.file.lastPathComponent).lineLimit(1) }
                    TableColumn("路径") { Text($0.file.path).lineLimit(1).truncationMode(.middle) }
                }
            } else {
                Table(model.results) {
                    TableColumn("来源") { Text($0.source.path).lineLimit(1).truncationMode(.middle) }
                    TableColumn("输出") { Text($0.destination?.path ?? "").lineLimit(1).truncationMode(.middle) }
                    TableColumn("结果") { Text($0.error ?? "成功").lineLimit(1) }.width(min: 100, ideal: 180)
                }
            }
        }
        .toolErrorAlert($model.errorMessage)
    }
}

struct SpreadsheetToolsView: View {
    @ObservedObject var model: SpreadsheetToolsWorkspaceModel

    var body: some View {
        ToolPage(title: "Excel 分组合并", subtitle: "按指定列分组，其他列去重后合并", icon: "tablecells", status: model.statusMessage) {
            HStack {
                ToolPathBox(label: "Excel 文件", url: model.workbookURL)
                Button("选择 Excel…", action: model.chooseWorkbook).disabled(model.isWorking)
            }
            HStack {
                Picker("分组列", selection: $model.groupingColumn) {
                    Text("请选择").tag(nil as XLSXColumn?)
                    ForEach(model.sheet?.columns ?? []) { Text($0.title).tag(Optional($0)) }
                }.frame(width: 260)
                Text("同组内其他列去重后以英文逗号连接，结果写入新的 XLSX。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("分组合并并导出…", action: model.exportGrouped)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.groupingColumn == nil || model.isWorking)
            }
        } content: {
            if let sheet = model.sheet {
                VStack(alignment: .leading, spacing: 8) {
                    Text("工作表预览 · \(sheet.rows.count) 行").font(.headline)
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                            GridRow { ForEach(sheet.columns) { Text($0.title).fontWeight(.semibold) } }
                            Divider()
                            ForEach(Array(sheet.rows.prefix(100).enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(sheet.columns) { column in
                                        Text(sheet.value(row: row, column: column)).lineLimit(1)
                                    }
                                }
                            }
                        }.padding(12)
                    }
                }.padding()
            }
        }
        .toolErrorAlert($model.errorMessage)
    }
}

private struct ToolPage<Controls: View, Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let status: String
    @ViewBuilder let controls: Controls
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            TaskHeader(title: title, subtitle: subtitle, systemImage: icon, tint: FileNestTheme.teal)
            Divider()
            VStack(alignment: .leading, spacing: 13) { controls }
                .padding(16)
                .background(FileNestTheme.panelBackground, in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(FileNestTheme.border) }
                .padding(.horizontal, WorkspaceLayout.leadingInset)
                .padding(.vertical, WorkspaceLayout.verticalInset)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Text(status).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WorkspaceLayout.leadingInset)
                .frame(height: FileNestTheme.statusBarHeight)
                .background(FileNestTheme.panelBackground)
        }
    }
}

private struct ToolDirectoryRow: View {
    let label: String
    let url: URL?
    let action: () -> Void
    var body: some View {
        HStack {
            ToolPathBox(label: label, url: url)
            Button("选择…", action: action)
        }
    }
}

private struct ToolPathBox: View {
    let label: String
    let url: URL?
    var body: some View {
        HStack {
            Image(systemName: url == nil ? "folder" : "folder.fill").foregroundStyle(.secondary)
            Text(url?.path ?? label).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10).frame(height: FileNestTheme.formControlHeight)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)) }
    }
}

private extension View {
    func toolErrorAlert(_ message: Binding<String?>) -> some View {
        alert("操作失败", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("好") { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}
