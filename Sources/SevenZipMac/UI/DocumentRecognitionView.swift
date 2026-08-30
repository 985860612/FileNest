import FileNestOCRCore
import SwiftUI

struct DocumentRecognitionView: View {
    @ObservedObject var model: DocumentRecognitionWorkspaceModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TaskHeader(
                title: "文档识别",
                subtitle: "原生 PP-StructureV3：OCR、版面、阅读顺序与表格结构",
                systemImage: "doc.text.magnifyingglass",
                tint: FileNestTheme.teal
            )
            Divider()
            controls
            Divider()
            if model.items.isEmpty { emptyState } else { results }
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
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(
                    model.modelsReady ? "模型已就绪" : "需要下载模型",
                    systemImage: model.modelsReady ? "checkmark.circle.fill" : "arrow.down.circle"
                )
                .foregroundStyle(model.modelsReady ? FileNestTheme.green : FileNestTheme.orange)
                Text("SDK \(DocumentRecognitionService.sdkVersion) · CPU 精确模式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isDownloading {
                    ProgressView().controlSize(.small)
                    Text(model.modelProgress).font(.caption).monospacedDigit()
                }
                Button(model.modelsReady ? "重新校验模型" : "下载模型", action: model.downloadModels)
                    .disabled(model.isDownloading || model.isWorking)
            }
            HStack(spacing: 16) {
                Stepper("并发 \(model.maxConcurrentDocuments)", value: $model.maxConcurrentDocuments, in: 1...4)
                    .frame(width: 120)
                Toggle("方向校正", isOn: $model.classifyOrientation).toggleStyle(.checkbox)
                Toggle("文档矫正", isOn: $model.unwarpDocument).toggleStyle(.checkbox)
                Toggle("表格结构", isOn: $model.recognizeTables).toggleStyle(.checkbox)
                Spacer()
                Picker("导出", selection: $model.exportFormat) {
                    ForEach(DocumentExportFormat.allCases) { format in Text(format.rawValue).tag(format) }
                }
                .frame(width: 150)
                Button("批量导出…", action: model.exportAll)
                    .disabled(model.isWorking || !model.items.contains { $0.result != nil })
                Button("开始识别", action: model.recognize)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking || model.isDownloading || !model.modelsReady || model.items.isEmpty)
            }
            Text("默认并发 2 是 M 系列 Mac 的内存/吞吐平衡点；CoreML 对当前 server 模型结果不一致，因此固定使用已验证的 CPU 路径。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(FileNestTheme.panelBackground, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(FileNestTheme.border) }
        .padding(.horizontal, WorkspaceLayout.leadingInset)
        .padding(.vertical, WorkspaceLayout.verticalInset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: dropTargeted ? "arrow.down.doc.fill" : "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(FileNestTheme.teal)
            Text("将图片、PDF 或文件夹拖到这里").font(.headline)
            Text("支持 PDF、PNG、JPEG、HEIC、TIFF、BMP 和 WebP，可递归扫描文件夹。")
                .font(.caption).foregroundStyle(.secondary)
            Button("选择文档…", action: model.chooseDocuments)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? FileNestTheme.teal.opacity(0.08) : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in model.add(urls); return true } isTargeted: { dropTargeted = $0 }
    }

    private var results: some View {
        Table(model.items) {
            TableColumn("文档") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.source.lastPathComponent).lineLimit(1)
                    Text(item.source.deletingLastPathComponent().path)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .contextMenu {
                    if item.result != nil { Button("导出 \(model.exportFormat.rawValue)…") { model.export(item) } }
                }
            }
            TableColumn("页/块") { item in
                Text(item.result == nil ? "—" : "\(item.pageCount) / \(item.blockCount)").monospacedDigit()
            }.width(70)
            TableColumn("耗时") { item in
                Text(item.seconds.map { String(format: "%.2f s", $0) } ?? "—").monospacedDigit()
            }.width(75)
            TableColumn("状态") { item in
                HStack(spacing: 6) {
                    if item.state == .processing { ProgressView().controlSize(.small) }
                    Text(item.state.label).lineLimit(1)
                }
            }.width(min: 110, ideal: 180)
            TableColumn("") { item in
                Button("导出…") { model.export(item) }.disabled(item.result == nil)
            }.width(65)
        }
        .dropDestination(for: URL.self) { urls, _ in model.add(urls); return true }
    }

    private var statusBar: some View {
        HStack {
            Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if !model.items.isEmpty {
                Button("添加…", action: model.chooseDocuments).buttonStyle(.link).disabled(model.isWorking)
                Button("清空", action: model.clear).buttonStyle(.link).disabled(model.isWorking)
            }
        }
        .padding(.horizontal, WorkspaceLayout.leadingInset)
        .frame(height: FileNestTheme.statusBarHeight)
        .background(FileNestTheme.panelBackground)
    }
}
