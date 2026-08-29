import AppKit
import SwiftUI

struct NCMConverterView: View {
    @ObservedObject var model: NCMWorkspaceModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TaskHeader(
                title: "NCM 转换",
                subtitle: "在本机恢复 NCM 中的原始 MP3 或 FLAC 音频",
                systemImage: AppDestination.ncmConversion.systemImage,
                tint: AppDestination.ncmConversion.tint
            )
            Divider()
            HStack(spacing: 0) {
                filePanel
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                settingsPanel
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
            }
            Divider()
            statusBar
        }
        .background(FileNestTheme.workspaceBackground)
        .alert("转换失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var filePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.items.isEmpty ? "NCM 文件" : "已选择 \(model.items.count) 个文件")
                    .font(.headline)
                Spacer()
                if !model.items.isEmpty {
                    Button("添加…", action: model.chooseFiles)
                        .buttonStyle(.link)
                        .disabled(model.isWorking)
                }
            }
            if model.items.isEmpty { dropZone } else { fileList }
        }
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, WorkspaceLayout.verticalInset)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppDestination.ncmConversion.tint.opacity(0.13))
                Image(systemName: dropTargeted ? "arrow.down" : AppDestination.ncmConversion.systemImage)
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(AppDestination.ncmConversion.tint)
            }
            .frame(width: 68, height: 68)
            .scaleEffect(dropTargeted ? 1.06 : 1)
            VStack(spacing: 5) {
                Text("将 NCM 文件或文件夹拖到这里")
                    .font(.title3.weight(.semibold))
                Text("自动恢复原始 MP3 / FLAC，支持批量处理")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("选择 NCM…", action: model.chooseFiles)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? AppDestination.ncmConversion.tint.opacity(0.10) : FileNestTheme.recessedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AppDestination.ncmConversion.tint : FileNestTheme.border,
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var fileList: some View {
        List {
            ForEach(model.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppDestination.ncmConversion.tint)
                        .frame(width: 32, height: 32)
                        .background(AppDestination.ncmConversion.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.source.lastPathComponent)
                            .lineLimit(1)
                        Text(item.source.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    stateView(item)
                    if !model.isWorking {
                        Button {
                            model.remove(item.source)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除 \(item.source.lastPathComponent)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(FileNestTheme.border) }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder
    private func stateView(_ item: NCMConversionItem) -> some View {
        switch item.state {
        case .waiting:
            Text("等待转换").foregroundStyle(.secondary)
        case .converting(let fraction):
            ProgressView(value: fraction)
                .frame(width: 86)
        case .completed(let output):
            Button {
                model.reveal(output)
            } label: {
                Label("完成", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(FileNestTheme.green)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")
        case .failed(let message):
            Label("失败", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(FileNestTheme.red)
                .help(message)
        case .cancelled:
            Text("已取消").foregroundStyle(.secondary)
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("输出位置", systemImage: "folder.fill")
                        .font(.headline)
                        .foregroundStyle(AppDestination.ncmConversion.tint)
                    Picker("", selection: $model.outputLocation) {
                        ForEach(NCMOutputLocation.allCases) { location in
                            Text(location.rawValue).tag(location)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    if model.outputLocation == .customDirectory {
                        Button(action: model.chooseOutputDirectory) {
                            HStack {
                                Image(systemName: "folder")
                                Text(model.outputDirectory?.path ?? "选择输出文件夹…")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                        .fileNestFormControl()
                    }
                }
                .padding(14)
                .background(FileNestTheme.panelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(FileNestTheme.border) }

                VStack(alignment: .leading, spacing: 9) {
                    Label("无损恢复", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                    Text("直接恢复缓存内的原始 MP3 或 FLAC，不重新编码，不降低音质。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    Label("完全本地", systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold))
                    Text("文件不会上传，也不会启动命令行转换工具。请仅处理你有权使用的音频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .background(AppDestination.ncmConversion.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
        }
        .background(FileNestTheme.sidebarBackground)
        .disabled(model.isWorking)
    }

    private var statusBar: some View {
        VStack(spacing: 7) {
            if model.isWorking { ProgressView(value: model.overallProgress) }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusMessage).font(.callout)
                    if model.isWorking, !model.currentFileName.isEmpty {
                        Text(model.currentFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if model.isWorking {
                    Button("取消", action: model.cancel)
                } else if model.hasCompletedBatch, let output = model.lastCompletedOutput {
                    Button("在 Finder 中显示") { model.reveal(output) }
                        .controlSize(.large)
                } else {
                    Button(model.hasRetryableItems ? "重试失败项" : "开始转换", action: model.start)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!model.canConvert)
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
