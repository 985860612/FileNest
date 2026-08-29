import AppKit
import SwiftUI

struct HashToolView: View {
    @ObservedObject var model: HashWorkspaceModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TaskHeader(
                title: "Hash 校验",
                subtitle: "计算并验证文件的 MD5、SHA-1、SHA-256 或 SHA-512",
                systemImage: AppDestination.hashVerification.systemImage,
                tint: AppDestination.hashVerification.tint
            )
            Divider()
            HStack(spacing: 0) {
                filePanel
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                settingsPanel
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
            Divider()
            statusBar
        }
        .background(FileNestTheme.workspaceBackground)
    }

    private var filePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selectedURLs.isEmpty ? "文件" : "已选择 \(model.selectedURLs.count) 个文件")
                    .font(.headline)
                Spacer()
                if !model.selectedURLs.isEmpty {
                    Button("添加…", action: model.chooseFiles)
                        .buttonStyle(.link)
                        .disabled(model.isWorking)
                }
            }
            if model.selectedURLs.isEmpty {
                dropZone
            } else if model.results.isEmpty {
                selectedFiles
            } else {
                resultsTable
            }
        }
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, WorkspaceLayout.verticalInset)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FileNestTheme.violet.opacity(0.13))
                Image(systemName: dropTargeted ? "arrow.down" : AppDestination.hashVerification.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FileNestTheme.violet)
            }
            .frame(width: 68, height: 68)
            VStack(spacing: 5) {
                Text("将文件拖到这里")
                    .font(.title3.weight(.semibold))
                Text("支持一次计算多个文件，全程在本机完成")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("选择文件…", action: model.chooseFiles)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? FileNestTheme.violet.opacity(0.10) : FileNestTheme.recessedBackground)
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

    private var selectedFiles: some View {
        List {
            ForEach(model.selectedURLs, id: \.self) { url in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
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
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)) }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: model.selectedURLs + urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var resultsTable: some View {
        Table(model.results) {
            TableColumn("文件") { result in
                Label(result.url.lastPathComponent, systemImage: result.digest == nil ? "exclamationmark.triangle" : "doc")
                    .lineLimit(1)
            }
            TableColumn("Hash") { result in
                if let digest = result.digest {
                    HStack(spacing: 7) {
                        Text(digest)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            copy(digest)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("复制 Hash")
                    }
                } else {
                    Text(result.errorMessage ?? "计算失败")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            TableColumn("校验") { result in
                verificationLabel(for: result)
            }
            .width(min: 70, ideal: 82)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.accept(urls: model.selectedURLs + urls)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("算法")
                        .font(.headline)
                    Picker("", selection: $model.algorithm) {
                        ForEach(HashAlgorithm.allCases) { algorithm in
                            Text(algorithm.rawValue).tag(algorithm)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fileNestFormControl()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("期望 Hash")
                        .font(.headline)
                    TextField("粘贴 Hash 进行校验（可选）", text: $model.expectedHash)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .fileNestFormControl()
                    Text("单文件校验时粘贴官网或发布页提供的 Hash；结果会自动忽略大小写。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("本地安全计算", systemImage: "lock.shield")
                        .font(.subheadline.weight(.medium))
                    Text("文件内容不会上传，也不会调用 md5、shasum 等命令行工具。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(20)
        }
        .background(FileNestTheme.sidebarBackground)
        .disabled(model.isWorking)
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            if model.isWorking { ProgressView() }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusMessage)
                        .font(.callout)
                    if model.isWorking, !model.currentFileName.isEmpty {
                        Text(model.currentFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("计算 \(model.algorithm.rawValue)", action: model.calculate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.canCalculate)
            }
        }
        .padding(.leading, WorkspaceLayout.leadingInset)
        .padding(.trailing, WorkspaceLayout.trailingInset)
        .padding(.vertical, 13)
        .frame(minHeight: FileNestTheme.statusBarHeight)
        .background(FileNestTheme.panelBackground)
    }

    @ViewBuilder
    private func verificationLabel(for result: FileHashResult) -> some View {
        if result.digest == nil {
            Label("失败", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        } else {
            switch model.verificationState(for: result) {
            case .notRequested:
                Text("—").foregroundStyle(.secondary)
            case .matched:
                Label("匹配", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .mismatched:
                Label("不匹配", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
