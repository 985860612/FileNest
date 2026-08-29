import AppKit
import Combine
import Foundation

@MainActor
final class FinderOperationModel: ObservableObject {
    let action: FinderAction
    let selectedURLs: [URL]

    @Published var format: ArchiveFormat
    @Published var password = ""
    @Published var compressionLevel = CompressionDefaults.level
    @Published var dictionarySize: CompressionDictionarySize = .automatic
    @Published var volumePreset: ArchiveVolumePreset = .none
    @Published var customVolumeMegabytes = 100
    @Published var excludeMacOSMetadata = true
    @Published var destinationURL: URL
    @Published var entries: [ArchiveEntry] = []
    @Published var searchText = ""
    @Published var browserPath = ""
    @Published var browserSelection: String?
    @Published var isLoadingContents = false
    @Published var isWorking = false
    @Published var progressFraction: Double?
    @Published var currentPath = ""
    @Published var statusMessage = "准备就绪"
    @Published var errorMessage: String?
    @Published var resultURLs: [URL] = []

    private let engine: ArchiveEngine
    private var cancellation: ArchiveCancellation?
    private var previewRequestID = UUID()

    init(request: FinderActionRequest, engine: ArchiveEngine = .shared) {
        action = request.action
        selectedURLs = request.urls
        self.engine = engine
        switch request.action {
        case .compress(let requestedFormat):
            format = requestedFormat
            destinationURL = ArchiveUtilities.archiveDestination(for: request.urls, format: requestedFormat)
        case .extract, .browse:
            format = .sevenZip
            destinationURL = request.urls.first.map(ArchiveUtilities.extractionFolder)
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        if request.action == .browse || request.action == .extract {
            Task { [weak self] in self?.loadContents() }
        }
    }

    var isBrowseOnly: Bool { action == .browse }
    var isCompression: Bool {
        if case .compress = action { return true }
        return false
    }
    var canStart: Bool {
        !isBrowseOnly
            && !selectedURLs.isEmpty
            && !isWorking
            && (volumePreset != .custom || (1...1_048_576).contains(customVolumeMegabytes))
            && !(isCompression && format == .tar && !password.isEmpty)
    }
    var actionTitle: String { isCompression ? "开始压缩" : "开始解压" }
    var volumeSize: UInt64 { volumePreset.bytes(customMegabytes: customVolumeMegabytes) }
    var effectiveDictionarySize: UInt64 { format == .sevenZip ? dictionarySize.rawValue : 0 }
    var browserItems: [ArchiveBrowserItem] {
        Self.browserItems(entries: entries, directory: browserPath, searchText: searchText)
    }
    var isBrowserSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var browserLocationTitle: String {
        if isBrowserSearching { return "搜索整个归档" }
        return browserPath.isEmpty ? "归档根目录" : "归档 / \(browserPath)"
    }
    var canBrowseUp: Bool {
        !browserPath.isEmpty && !isBrowserSearching
    }
    var selectionSummary: String {
        selectedURLs.count == 1 ? selectedURLs[0].lastPathComponent : "已选择 \(selectedURLs.count) 项"
    }

    func setFormat(_ newFormat: ArchiveFormat) {
        guard format != newFormat else { return }
        format = newFormat
        let base = destinationURL.deletingPathExtension()
        destinationURL = base.appendingPathExtension(newFormat.fileExtension)
    }

    func chooseDestination() {
        if isCompression {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.prompt = "选择"
            panel.nameFieldStringValue = destinationURL.lastPathComponent
            panel.directoryURL = destinationURL.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationURL = url.pathExtension.isEmpty ? url.appendingPathExtension(format.fileExtension) : url
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "选择"
            panel.directoryURL = destinationURL.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationURL = selectedURLs.count == 1
                ? url.appendingPathComponent(Self.defaultExtractionName(for: selectedURLs[0]), isDirectory: true)
                : url
        }
    }

    func loadContents() {
        guard selectedURLs.count == 1, let archive = selectedURLs.first,
              ArchiveUtilities.looksLikeArchive(archive) else { return }
        previewRequestID = UUID()
        let requestID = previewRequestID
        let password = password
        let engine = engine
        isLoadingContents = true
        errorMessage = nil
        statusMessage = "正在读取归档目录…"
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let loadedEntries = try engine.list(archive: archive, password: password)
                await self?.finishLoading(entries: loadedEntries, requestID: requestID)
            } catch {
                await self?.finishLoading(error: error.localizedDescription, requestID: requestID)
            }
        }
    }

    func start() {
        guard canStart else { return }
        let token = ArchiveCancellation()
        cancellation = token
        isWorking = true
        progressFraction = nil
        currentPath = "准备中…"
        statusMessage = isCompression ? "正在创建归档…" : "正在解压…"
        errorMessage = nil
        resultURLs = []

        let action = action
        let inputs = selectedURLs
        let destination = destinationURL
        let password = password
        let format = format
        let level = Int(compressionLevel)
        let dictionarySize = effectiveDictionarySize
        let excludeMacOSMetadata = excludeMacOSMetadata
        let volumeSize = volumeSize
        let engine = engine

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let outputs: [URL]
                switch action {
                case .compress:
                    try engine.compress(
                        inputs: inputs,
                        to: destination,
                        format: format,
                        password: password,
                        level: level,
                        dictionarySize: dictionarySize,
                        excludeMacOSMetadata: excludeMacOSMetadata,
                        volumeSize: volumeSize,
                        cancellation: token,
                        progress: Self.progressHandler(for: self)
                    )
                    outputs = [volumeSize > 0
                        ? ArchiveVolumeUtilities.firstVolumeURL(for: destination)
                        : destination]
                case .extract:
                    var extracted: [URL] = []
                    for (index, archive) in inputs.enumerated() {
                        let output = Self.extractionDestination(
                            for: archive,
                            selectedDestination: destination,
                            inputCount: inputs.count
                        )
                        try engine.extract(
                            archive: archive,
                            to: output,
                            password: password,
                            cancellation: token,
                            progress: Self.progressHandler(for: self, index: index, count: inputs.count)
                        )
                        extracted.append(output)
                    }
                    outputs = extracted
                case .browse:
                    return
                }
                await self?.finishSuccessfully(outputs: outputs)
            } catch {
                await self?.finishWithError(error.localizedDescription)
            }
        }
    }

    func cancel() {
        cancellation?.cancel()
        statusMessage = "正在取消…"
    }

    func revealResults() {
        guard !resultURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(resultURLs)
    }

    func openBrowserItem(_ item: ArchiveBrowserItem) {
        guard item.directory else { return }
        browserPath = item.path
        browserSelection = nil
        searchText = ""
    }

    func browseUp() {
        guard canBrowseUp else { return }
        browserPath = browserPath.split(separator: "/").dropLast().joined(separator: "/")
        browserSelection = nil
    }

    nonisolated static func browserItems(
        entries: [ArchiveEntry],
        directory: String,
        searchText: String
    ) -> [ArchiveBrowserItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return entries
                .filter { $0.path.localizedCaseInsensitiveContains(query) }
                .map(ArchiveBrowserItem.init(entry:))
                .sorted(by: ArchiveBrowserItem.areInDisplayOrder)
        }

        let normalizedDirectory = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedDirectory.isEmpty ? "" : normalizedDirectory + "/"
        var children: [String: ArchiveBrowserItem] = [:]

        for entry in entries {
            let normalizedPath = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard normalizedPath.hasPrefix(prefix) else { continue }
            let remainder = String(normalizedPath.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            let parts = remainder.split(separator: "/", maxSplits: 1)
            guard let firstPart = parts.first else { continue }
            let name = String(firstPart)
            let childPath = prefix + name
            let isImplicitDirectory = parts.count > 1
            let candidate = ArchiveBrowserItem(
                path: childPath,
                name: name,
                size: isImplicitDirectory ? 0 : entry.size,
                directory: isImplicitDirectory || entry.directory
            )
            if let existing = children[childPath] {
                if candidate.directory && !existing.directory { children[childPath] = candidate }
            } else {
                children[childPath] = candidate
            }
        }
        return children.values.sorted(by: ArchiveBrowserItem.areInDisplayOrder)
    }

    nonisolated static func extractionDestination(
        for archive: URL,
        selectedDestination: URL,
        inputCount: Int
    ) -> URL {
        guard inputCount > 1 else { return selectedDestination }
        return selectedDestination.appendingPathComponent(defaultExtractionName(for: archive), isDirectory: true)
    }

    nonisolated static func defaultExtractionName(for archive: URL) -> String {
        let source = ArchiveVolumeUtilities.isFirstVolume(archive) ? archive.deletingPathExtension() : archive
        var stem = source.deletingPathExtension().lastPathComponent
        if ["gz", "bz2", "xz"].contains(source.pathExtension.lowercased()),
           stem.lowercased().hasSuffix(".tar") {
            stem = String(stem.dropLast(4))
        }
        return stem
    }

    private func finishLoading(entries: [ArchiveEntry], requestID: UUID) {
        guard previewRequestID == requestID else { return }
        self.entries = entries
        isLoadingContents = false
        statusMessage = "归档包含 \(entries.count) 项"
    }

    private func finishLoading(error: String, requestID: UUID) {
        guard previewRequestID == requestID else { return }
        entries = []
        isLoadingContents = false
        errorMessage = error
        statusMessage = "无法读取归档目录"
    }

    private func finishSuccessfully(outputs: [URL]) {
        resultURLs = outputs
        isWorking = false
        cancellation = nil
        progressFraction = 1
        currentPath = outputs.first?.lastPathComponent ?? ""
        statusMessage = "操作完成"
    }

    private func finishWithError(_ message: String) {
        isWorking = false
        cancellation = nil
        errorMessage = message
        statusMessage = message == "Cancelled" ? "已取消" : "操作失败"
    }

    private nonisolated static func progressHandler(
        for model: FinderOperationModel?,
        index: Int = 0,
        count: Int = 1
    ) -> @Sendable (ArchiveProgress) -> Void {
        { [weak model] progress in
            let combinedFraction = progress.fraction.map { (Double(index) + $0) / Double(max(1, count)) }
            Task { @MainActor in
                guard let model else { return }
                model.progressFraction = monotonicProgress(
                    current: model.progressFraction,
                    incoming: combinedFraction
                )
                if let path = progress.currentPath, !path.isEmpty {
                    model.currentPath = path
                }
            }
        }
    }

    nonisolated static func monotonicProgress(current: Double?, incoming: Double?) -> Double? {
        guard let incoming else { return current }
        return max(current ?? 0, incoming)
    }
}

struct ArchiveBrowserItem: Identifiable, Sendable {
    let path: String
    let name: String
    let size: UInt64
    let directory: Bool

    var id: String { path }

    init(path: String, name: String, size: UInt64, directory: Bool) {
        self.path = path
        self.name = name
        self.size = size
        self.directory = directory
    }

    init(entry: ArchiveEntry) {
        path = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        name = path.split(separator: "/").last.map(String.init) ?? path
        size = entry.size
        directory = entry.directory
    }

    static func areInDisplayOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.directory != rhs.directory { return lhs.directory }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
