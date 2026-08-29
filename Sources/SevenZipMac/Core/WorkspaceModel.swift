import AppKit
import Combine
import Foundation

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var mode: WorkspaceMode = .extract
    @Published var selectedURLs: [URL] = []
    @Published var format: ArchiveFormat = .sevenZip
    @Published var password = ""
    @Published var compressionLevel = CompressionDefaults.level
    @Published var dictionarySize: CompressionDictionarySize = .automatic
    @Published var volumePreset: ArchiveVolumePreset = .none
    @Published var customVolumeMegabytes = 100
    @Published var excludeMacOSMetadata = true
    @Published var isWorking = false
    @Published var progressFraction: Double?
    @Published var currentPath = ""
    @Published var statusMessage = "把文件拖到这里，或从 Finder 选择"
    @Published var errorMessage: String?
    @Published var archiveEntries: [ArchiveEntry] = []
    @Published var isLoadingArchiveContents = false
    @Published var archivePreviewError: String?

    private var cancellation: ArchiveCancellation?
    private var previewRequestID = UUID()
    private let engine: ArchiveEngine

    init(engine: ArchiveEngine = .shared) {
        self.engine = engine
        NotificationCenter.default.addObserver(
            forName: .sevenZipMacOpenURLs,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let urls = notification.object as? [URL] else { return }
            Task { @MainActor in self?.accept(urls: urls) }
        }
    }

    var canStart: Bool {
        !selectedURLs.isEmpty
            && !isWorking
            && (volumePreset != .custom || (1...1_048_576).contains(customVolumeMegabytes))
    }

    var volumeSize: UInt64 { volumePreset.bytes(customMegabytes: customVolumeMegabytes) }

    var effectiveDictionarySize: UInt64 {
        format == .sevenZip ? dictionarySize.rawValue : 0
    }

    var actionTitle: String {
        switch mode {
        case .extract: "解压"
        case .compress: "压缩为 \(format.displayName)"
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "选择"
        guard panel.runModal() == .OK else { return }
        accept(urls: panel.urls)
    }

    func accept(urls: [URL]) {
        let normalized = urls.map { $0.standardizedFileURL }
        selectedURLs = Array(NSOrderedSet(array: normalized).array.compactMap { $0 as? URL })
        if selectedURLs.count == 1, ArchiveUtilities.looksLikeArchive(selectedURLs[0]) {
            mode = .extract
        } else {
            mode = .compress
        }
        statusMessage = "已选择 \(selectedURLs.count) 项"
        errorMessage = nil
        refreshArchiveContents()
    }

    func remove(_ url: URL) {
        selectedURLs.removeAll { $0 == url }
        if selectedURLs.isEmpty {
            statusMessage = "把文件拖到这里，或从 Finder 选择"
        }
        refreshArchiveContents()
    }

    func clear() {
        selectedURLs.removeAll()
        errorMessage = nil
        statusMessage = "把文件拖到这里，或从 Finder 选择"
        resetArchivePreview()
    }

    func refreshArchiveContents() {
        previewRequestID = UUID()
        let requestID = previewRequestID
        guard mode == .extract,
              selectedURLs.count == 1,
              let archive = selectedURLs.first,
              ArchiveUtilities.looksLikeArchive(archive)
        else {
            archiveEntries = []
            archivePreviewError = nil
            isLoadingArchiveContents = false
            return
        }

        archiveEntries = []
        archivePreviewError = nil
        isLoadingArchiveContents = true
        statusMessage = "正在读取归档内容…"
        let password = password
        let engine = engine

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let entries = try engine.list(archive: archive, password: password)
                DispatchQueue.main.async {
                    guard let self, self.previewRequestID == requestID else { return }
                    self.archiveEntries = entries
                    self.isLoadingArchiveContents = false
                    self.statusMessage = "归档包含 \(entries.count) 项"
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.previewRequestID == requestID else { return }
                    self.archivePreviewError = error.localizedDescription
                    self.isLoadingArchiveContents = false
                    self.statusMessage = "无法读取归档内容"
                }
            }
        }
    }

    func start() {
        guard canStart else { return }
        if mode == .extract, selectedURLs.contains(where: { !ArchiveUtilities.looksLikeArchive($0) }) {
            errorMessage = "解压模式只能选择受支持的归档文件。"
            return
        }
        isWorking = true
        errorMessage = nil
        progressFraction = nil
        currentPath = "准备中…"
        let token = ArchiveCancellation()
        cancellation = token
        let inputs = selectedURLs
        let password = password
        let selectedFormat = format
        let level = Int(compressionLevel)
        let dictionarySize = effectiveDictionarySize
        let excludeMacOSMetadata = excludeMacOSMetadata
        let volumeSize = volumeSize
        let engine = engine
        let selectedMode = mode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let output: URL
                switch selectedMode {
                case .extract:
                    var lastOutput = ArchiveUtilities.extractionFolder(for: inputs[0])
                    for input in inputs {
                        let destination = ArchiveUtilities.extractionFolder(for: input)
                        try engine.extract(
                            archive: input,
                            to: destination,
                            password: password,
                            cancellation: token,
                            progress: Self.progressHandler(for: self)
                        )
                        lastOutput = destination
                    }
                    output = lastOutput
                case .compress:
                    let destination = ArchiveUtilities.archiveDestination(
                        for: inputs,
                        format: selectedFormat,
                        volumeSize: volumeSize
                    )
                    try engine.compress(
                        inputs: inputs,
                        to: destination,
                        format: selectedFormat,
                        password: password,
                        level: level,
                        dictionarySize: dictionarySize,
                        excludeMacOSMetadata: excludeMacOSMetadata,
                        volumeSize: volumeSize,
                        cancellation: token,
                        progress: Self.progressHandler(for: self)
                    )
                    output = volumeSize > 0
                        ? ArchiveVolumeUtilities.firstVolumeURL(for: destination)
                        : destination
                }
                DispatchQueue.main.async {
                    self?.finishSuccessfully(output: output)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishWithError(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        cancellation?.cancel()
        statusMessage = "正在取消…"
    }

    private nonisolated static func progressHandler(for model: WorkspaceModel?) -> @Sendable (ArchiveProgress) -> Void {
        { progress in
            DispatchQueue.main.async {
                model?.progressFraction = progress.fraction
                if let path = progress.currentPath, !path.isEmpty {
                    model?.currentPath = path
                }
            }
        }
    }

    private func finishSuccessfully(output: URL) {
        isWorking = false
        cancellation = nil
        progressFraction = 1
        currentPath = output.lastPathComponent
        statusMessage = "完成"
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    private func finishWithError(_ message: String) {
        isWorking = false
        cancellation = nil
        errorMessage = message
        statusMessage = message == "Cancelled" ? "已取消" : "操作失败"
    }

    private func resetArchivePreview() {
        previewRequestID = UUID()
        archiveEntries = []
        archivePreviewError = nil
        isLoadingArchiveContents = false
    }
}

extension Notification.Name {
    static let sevenZipMacOpenURLs = Notification.Name("SevenZipMacOpenURLs")
}
