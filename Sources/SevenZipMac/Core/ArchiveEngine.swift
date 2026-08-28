import Darwin
import Foundation

private typealias CProgressCallback = @convention(c) (
    UInt64, UInt64, UnsafePointer<CChar>?, UnsafeMutableRawPointer?
) -> Void
private typealias CCancelCallback = @convention(c) (UnsafeMutableRawPointer?) -> Int32

private typealias CExtractFunction = @convention(c) (
    UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
    CProgressCallback?, CCancelCallback?, UnsafeMutableRawPointer?
) -> Int32
private typealias CCompressFunction = @convention(c) (
    UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
    UnsafePointer<UnsafePointer<CChar>?>?, Int,
    UnsafePointer<CChar>?, Int32, UInt64,
    Int32,
    CProgressCallback?, CCancelCallback?, UnsafeMutableRawPointer?
) -> Int32
private typealias CListFunction = @convention(c) (
    UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?
private typealias CLastErrorFunction = @convention(c) () -> UnsafePointer<CChar>?
private typealias CFreeFunction = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

private final class CallbackBox: @unchecked Sendable {
    let cancellation: ArchiveCancellation
    let progress: @Sendable (ArchiveProgress) -> Void

    init(cancellation: ArchiveCancellation, progress: @escaping @Sendable (ArchiveProgress) -> Void) {
        self.cancellation = cancellation
        self.progress = progress
    }
}

private let progressTrampoline: CProgressCallback = { completed, total, currentPath, context in
    guard let context else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
    box.progress(ArchiveProgress(
        completed: completed,
        total: total,
        currentPath: currentPath.map { String(cString: $0) }
    ))
}

private let cancelTrampoline: CCancelCallback = { context in
    guard let context else { return 0 }
    let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
    return box.cancellation.isCancelled ? 1 : 0
}

final class ArchiveEngine: @unchecked Sendable {
    static let shared = ArchiveEngine()

    private let handle: UnsafeMutableRawPointer
    private let enginePath: String
    private let extractFunction: CExtractFunction
    private let compressFunction: CCompressFunction
    private let listFunction: CListFunction
    private let lastErrorFunction: CLastErrorFunction
    private let freeFunction: CFreeFunction

    init(engineDirectory: URL? = nil) {
        let directory = engineDirectory ?? Self.defaultEngineDirectory
        enginePath = directory.appendingPathComponent("7z.so").path
        let bridgePath = directory.appendingPathComponent("libsevenzipbridge.dylib").path
        guard let opened = dlopen(bridgePath, RTLD_NOW | RTLD_LOCAL) else {
            fatalError("无法加载 7-Zip 桥接：\(String(cString: dlerror()))")
        }
        handle = opened
        extractFunction = Self.load("sz_extract", from: opened)
        compressFunction = Self.load("sz_compress", from: opened)
        listFunction = Self.load("sz_list_json", from: opened)
        lastErrorFunction = Self.load("sz_last_error", from: opened)
        freeFunction = Self.load("sz_free_string", from: opened)
    }

    deinit { dlclose(handle) }

    func extract(
        archive: URL,
        to destination: URL,
        password: String,
        cancellation: ArchiveCancellation,
        progress: @escaping @Sendable (ArchiveProgress) -> Void
    ) throws {
        let prepared = try ArchiveVolumeUtilities.prepareForReading(
            archive,
            cancellation: cancellation,
            progress: progress
        )
        defer { prepared.cleanUp() }
        let box = CallbackBox(cancellation: cancellation, progress: progress)
        let context = Unmanaged.passUnretained(box).toOpaque()
        let result = enginePath.withCString { engine in
            prepared.url.path.withCString { archivePath in
                destination.path.withCString { destinationPath in
                    password.withCString { passwordPointer in
                        extractFunction(
                            engine, archivePath, destinationPath,
                            password.isEmpty ? nil : passwordPointer,
                            progressTrampoline, cancelTrampoline, context
                        )
                    }
                }
            }
        }
        guard result == 0 else { throw ArchiveEngineError.operationFailed(lastError()) }
    }

    func compress(
        inputs: [URL],
        to destination: URL,
        format: ArchiveFormat,
        password: String,
        level: Int,
        dictionarySize: UInt64,
        excludeMacOSMetadata: Bool = true,
        volumeSize: UInt64,
        cancellation: ArchiveCancellation,
        progress: @escaping @Sendable (ArchiveProgress) -> Void
    ) throws {
        let strings = inputs.map { strdup($0.path) }
        defer { strings.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = strings.map { pointer in
            guard let pointer else { return nil }
            return UnsafePointer<CChar>(pointer)
        }
        let box = CallbackBox(cancellation: cancellation, progress: progress)
        let context = Unmanaged.passUnretained(box).toOpaque()
        let result = enginePath.withCString { engine in
            destination.path.withCString { destinationPath in
                format.rawValue.withCString { formatPointer in
                    password.withCString { passwordPointer in
                        pointers.withUnsafeBufferPointer { buffer in
                            compressFunction(
                                engine, destinationPath, formatPointer,
                                buffer.baseAddress, buffer.count,
                                password.isEmpty ? nil : passwordPointer,
                                Int32(level), dictionarySize,
                                excludeMacOSMetadata ? 1 : 0,
                                progressTrampoline, cancelTrampoline, context
                            )
                        }
                    }
                }
            }
        }
        guard result == 0 else { throw ArchiveEngineError.operationFailed(lastError()) }
        if volumeSize > 0 {
            do {
                try ArchiveVolumeUtilities.split(
                    archive: destination,
                    volumeSize: volumeSize,
                    cancellation: cancellation,
                    progress: progress
                )
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }

    func list(archive: URL, password: String = "") throws -> [ArchiveEntry] {
        let prepared = try ArchiveVolumeUtilities.prepareForReading(
            archive,
            cancellation: ArchiveCancellation(),
            progress: { _ in }
        )
        defer { prepared.cleanUp() }
        let pointer = enginePath.withCString { engine in
            prepared.url.path.withCString { archivePath in
                password.withCString { passwordPointer in
                    listFunction(engine, archivePath, password.isEmpty ? nil : passwordPointer)
                }
            }
        }
        guard let pointer else { throw ArchiveEngineError.operationFailed(lastError()) }
        defer { freeFunction(pointer) }
        return try JSONDecoder().decode([ArchiveEntry].self, from: Data(bytes: pointer, count: strlen(pointer)))
    }

    private func lastError() -> String {
        lastErrorFunction().map { String(cString: $0) } ?? "未知的 7-Zip 错误"
    }

    private static var defaultEngineDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SEVENZIP_ENGINE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let frameworks = Bundle.main.privateFrameworksURL,
           FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("7z.so").path) {
            return frameworks
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/engine", isDirectory: true)
    }

    private static func load<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T {
        guard let symbol = dlsym(handle, name) else {
            fatalError("7-Zip 桥接缺少符号：\(name)")
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}
