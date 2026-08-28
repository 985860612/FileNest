import AppKit
import Combine
import CryptoKit
import Foundation

enum HashAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    case sha512 = "SHA-512"

    var id: String { rawValue }

    var hexadecimalLength: Int {
        switch self {
        case .md5: 32
        case .sha1: 40
        case .sha256: 64
        case .sha512: 128
        }
    }
}

struct FileHashResult: Identifiable, Sendable {
    let url: URL
    let digest: String?
    let errorMessage: String?

    var id: URL { url }
}

enum HashVerificationState: Equatable {
    case notRequested
    case matched
    case mismatched
}

enum FileHashService {
    static func digest(file: URL, algorithm: HashAlgorithm) throws -> String {
        switch algorithm {
        case .md5: try digest(file: file, using: Insecure.MD5.self)
        case .sha1: try digest(file: file, using: Insecure.SHA1.self)
        case .sha256: try digest(file: file, using: SHA256.self)
        case .sha512: try digest(file: file, using: SHA512.self)
        }
    }

    private static func digest<H: HashFunction>(file: URL, using type: H.Type) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = H()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class HashWorkspaceModel: ObservableObject {
    @Published var selectedURLs: [URL] = []
    @Published var algorithm: HashAlgorithm = .sha256 {
        didSet {
            if algorithm != oldValue {
                results = []
                statusMessage = selectedURLs.isEmpty ? "拖入文件以计算 Hash" : "算法已更改，请重新计算"
            }
        }
    }
    @Published var expectedHash = ""
    @Published var results: [FileHashResult] = []
    @Published var isWorking = false
    @Published var currentFileName = ""
    @Published var statusMessage = "拖入文件以计算 Hash"

    var canCalculate: Bool { !selectedURLs.isEmpty && !isWorking }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK else { return }
        accept(urls: panel.urls)
    }

    func accept(urls: [URL]) {
        let files = urls
            .map(\.standardizedFileURL)
            .filter { !$0.hasDirectoryPath }
        selectedURLs = Array(NSOrderedSet(array: files).array.compactMap { $0 as? URL })
        results = []
        statusMessage = selectedURLs.isEmpty ? "请选择文件，文件夹无法直接计算 Hash" : "已选择 \(selectedURLs.count) 个文件"
    }

    func remove(_ url: URL) {
        selectedURLs.removeAll { $0 == url }
        results.removeAll { $0.url == url }
        statusMessage = selectedURLs.isEmpty ? "拖入文件以计算 Hash" : "已选择 \(selectedURLs.count) 个文件"
    }

    func clear() {
        selectedURLs = []
        results = []
        expectedHash = ""
        currentFileName = ""
        statusMessage = "拖入文件以计算 Hash"
    }

    func calculate() {
        guard canCalculate else { return }
        let files = selectedURLs
        let algorithm = algorithm
        isWorking = true
        results = []
        statusMessage = "正在计算 \(algorithm.rawValue)…"

        Task.detached(priority: .userInitiated) { [weak self, files, algorithm] in
            var calculated: [FileHashResult] = []
            for file in files {
                await self?.updateCurrentFileName(file.lastPathComponent)
                do {
                    calculated.append(FileHashResult(
                        url: file,
                        digest: try FileHashService.digest(file: file, algorithm: algorithm),
                        errorMessage: nil
                    ))
                } catch {
                    calculated.append(FileHashResult(url: file, digest: nil, errorMessage: error.localizedDescription))
                }
            }
            await self?.finishCalculation(with: calculated)
        }
    }

    private func updateCurrentFileName(_ fileName: String) {
        currentFileName = fileName
    }

    private func finishCalculation(with calculated: [FileHashResult]) {
        results = calculated
        isWorking = false
        currentFileName = ""
        let failures = calculated.filter { $0.digest == nil }.count
        statusMessage = failures == 0
            ? "已完成 \(calculated.count) 个文件"
            : "完成，\(failures) 个文件计算失败"
    }

    func verificationState(for result: FileHashResult) -> HashVerificationState {
        guard let digest = result.digest else { return .mismatched }
        let expected = normalizedExpectedHash()
        guard !expected.isEmpty else { return .notRequested }
        return digest.caseInsensitiveCompare(expected) == .orderedSame ? .matched : .mismatched
    }

    private func normalizedExpectedHash() -> String {
        let parts = expectedHash.lowercased().split { !$0.isHexDigit }
        return parts.first { $0.count == algorithm.hexadecimalLength }.map(String.init) ?? ""
    }
}
