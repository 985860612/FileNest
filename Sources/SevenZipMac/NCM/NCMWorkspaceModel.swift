import AppKit
import Foundation

enum NCMOutputLocation: String, CaseIterable, Identifiable {
    case besideSource = "源文件旁"
    case customDirectory = "指定文件夹"

    var id: String { rawValue }
}

enum NCMConversionState: Equatable, Sendable {
    case waiting
    case converting(Double)
    case completed(URL)
    case failed(String)
    case cancelled
}

struct NCMConversionItem: Identifiable, Equatable, Sendable {
    let source: URL
    var state: NCMConversionState

    var id: URL { source }
}

@MainActor
final class NCMWorkspaceModel: ObservableObject {
    @Published var items: [NCMConversionItem] = []
    @Published var outputLocation: NCMOutputLocation = .besideSource
    @Published var outputDirectory: URL?
    @Published var isWorking = false
    @Published var overallProgress = 0.0
    @Published var currentFileName = ""
    @Published var statusMessage = "拖入 NCM 文件开始转换"
    @Published var errorMessage: String?

    private var cancellation: NCMCancellation?

    var canConvert: Bool {
        !pendingSources.isEmpty
            && !isWorking
            && (outputLocation == .besideSource || outputDirectory != nil)
    }

    var hasCompletedBatch: Bool { !items.isEmpty && pendingSources.isEmpty && !isWorking }

    var hasRetryableItems: Bool {
        items.contains { item in
            switch item.state {
            case .failed, .cancelled: true
            default: false
            }
        }
    }

    var lastCompletedOutput: URL? {
        items.reversed().compactMap { item in
            if case .completed(let output) = item.state { return output }
            return nil
        }.first
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = []
        panel.prompt = "选择"
        guard panel.runModal() == .OK else { return }
        accept(urls: panel.urls)
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择输出文件夹"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        outputDirectory = directory
        outputLocation = .customDirectory
    }

    func accept(urls: [URL]) {
        guard !isWorking else { return }
        let discovered = Self.discoverNCMFiles(in: urls)
        let existing = Set(items.map(\.source))
        let additions = discovered
            .filter { !existing.contains($0) }
            .map { NCMConversionItem(source: $0, state: .waiting) }
        items.append(contentsOf: additions)
        items.sort { $0.source.lastPathComponent.localizedStandardCompare($1.source.lastPathComponent) == .orderedAscending }
        statusMessage = items.isEmpty ? "没有找到 NCM 文件" : "已选择 \(items.count) 个 NCM 文件"
    }

    func remove(_ source: URL) {
        guard !isWorking else { return }
        items.removeAll { $0.source == source }
        statusMessage = items.isEmpty ? "拖入 NCM 文件开始转换" : "已选择 \(items.count) 个 NCM 文件"
    }

    func clear() {
        guard !isWorking else { return }
        items = []
        overallProgress = 0
        currentFileName = ""
        statusMessage = "拖入 NCM 文件开始转换"
        errorMessage = nil
    }

    func start() {
        guard canConvert else { return }
        let sources = pendingSources
        let location = outputLocation
        let selectedDirectory = outputDirectory
        let token = NCMCancellation()
        cancellation = token
        isWorking = true
        overallProgress = 0
        errorMessage = nil
        for index in items.indices where sources.contains(items[index].source) {
            items[index].state = .waiting
        }
        statusMessage = "正在转换 0/\(sources.count)"

        Task.detached(priority: .userInitiated) { [weak self, sources] in
            var completed = 0
            var failures = 0
            for (index, source) in sources.enumerated() {
                if token.isCancelled { break }
                await self?.begin(source: source, index: index, total: sources.count)
                let destination = location == .besideSource
                    ? source.deletingLastPathComponent()
                    : selectedDirectory!
                do {
                    let output = try NCMConversionService.convert(
                        source: source,
                        destinationDirectory: destination,
                        cancellation: token
                    ) { fraction in
                        Task { @MainActor [weak self] in
                            self?.update(source: source, index: index, total: sources.count, fraction: fraction)
                        }
                    }
                    completed += 1
                    await self?.finish(source: source, state: .completed(output.url))
                } catch NCMConversionError.cancelled {
                    await self?.finish(source: source, state: .cancelled)
                    break
                } catch {
                    failures += 1
                    await self?.finish(source: source, state: .failed(error.localizedDescription))
                }
            }
            await self?.finishBatch(completed: completed, failures: failures, cancelled: token.isCancelled)
        }
    }

    func cancel() {
        cancellation?.cancel()
        statusMessage = "正在取消…"
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func begin(source: URL, index: Int, total: Int) {
        currentFileName = source.lastPathComponent
        if let itemIndex = items.firstIndex(where: { $0.source == source }) {
            items[itemIndex].state = .converting(0)
        }
        statusMessage = "正在转换 \(index + 1)/\(total)"
    }

    private func update(source: URL, index: Int, total: Int, fraction: Double) {
        guard isWorking,
              let itemIndex = items.firstIndex(where: { $0.source == source }),
              case .converting = items[itemIndex].state else { return }
        let monotonic = max(items[itemIndex].progress, min(1, fraction))
        items[itemIndex].state = .converting(monotonic)
        overallProgress = min(1, (Double(index) + monotonic) / Double(total))
    }

    private func finish(source: URL, state: NCMConversionState) {
        guard let index = items.firstIndex(where: { $0.source == source }) else { return }
        items[index].state = state
    }

    private func finishBatch(completed: Int, failures: Int, cancelled: Bool) {
        if cancelled {
            for index in items.indices where items[index].state == .waiting {
                items[index].state = .cancelled
            }
        }
        isWorking = false
        cancellation = nil
        currentFileName = ""
        overallProgress = items.isEmpty
            ? 0
            : (cancelled ? Double(completed + failures) / Double(items.count) : 1)
        if cancelled {
            statusMessage = "已取消，完成 \(completed) 个文件"
        } else if failures == 0 {
            statusMessage = "转换完成，共 \(completed) 个文件"
        } else {
            statusMessage = "转换完成：成功 \(completed) 个，失败 \(failures) 个"
        }
    }

    nonisolated static func discoverNCMFiles(in urls: [URL]) -> [URL] {
        var files: [URL] = []
        let fileManager = FileManager.default
        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if url.pathExtension.caseInsensitiveCompare("ncm") == .orderedSame { files.append(url) }
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let candidate as URL in enumerator {
                if candidate.pathExtension.caseInsensitiveCompare("ncm") == .orderedSame {
                    files.append(candidate.standardizedFileURL)
                }
            }
        }
        return Array(Set(files)).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private var pendingSources: [URL] {
        items.compactMap { item in
            if case .completed = item.state { return nil }
            return item.source
        }
    }
}

private extension NCMConversionItem {
    var progress: Double {
        if case .converting(let value) = state { return value }
        if case .completed = state { return 1 }
        return 0
    }
}
