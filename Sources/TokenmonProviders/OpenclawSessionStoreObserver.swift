import Darwin
import Foundation

public struct OpenclawSessionStoreObserverConfig: Sendable {
    public let sessionsRootPath: String
    public let outputPath: String
    public let rescanDebounceDelay: DispatchTimeInterval
    public let fileProcessDebounceDelay: DispatchTimeInterval
    public let onActivityPulse: (@Sendable () -> Void)?

    public init(
        sessionsRootPath: String,
        outputPath: String,
        rescanDebounceDelay: DispatchTimeInterval = .milliseconds(150),
        fileProcessDebounceDelay: DispatchTimeInterval = .milliseconds(120),
        onActivityPulse: (@Sendable () -> Void)? = nil
    ) {
        self.sessionsRootPath = sessionsRootPath
        self.outputPath = outputPath
        self.rescanDebounceDelay = rescanDebounceDelay
        self.fileProcessDebounceDelay = fileProcessDebounceDelay
        self.onActivityPulse = onActivityPulse
    }
}

private struct OpenclawTrackedSessionFile {
    var sessionID: String
    var offset: Int64
    var lineNumber: Int
    let startedDuringLiveRuntime: Bool
}

public final class OpenclawSessionStoreObserver: @unchecked Sendable {
    private let config: OpenclawSessionStoreObserverConfig
    private let workerQueue = DispatchQueue(label: "TokenmonProviders.OpenclawSessionStoreObserver")

    private let configurationRootPath: String
    private var directorySources: [String: DispatchSourceFileSystemObject] = [:]
    private var directoryDescriptors: [String: CInt] = [:]
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: CInt] = [:]
    private var trackedFiles: [String: OpenclawTrackedSessionFile] = [:]
    private var pendingRescanWorkItem: DispatchWorkItem?
    private var pendingFileWorkItems: [String: DispatchWorkItem] = [:]
    private var initialScanCompleted = false

    public init(config: OpenclawSessionStoreObserverConfig) {
        self.config = config
        configurationRootPath = URL(fileURLWithPath: config.sessionsRootPath, isDirectory: true)
            .deletingLastPathComponent()
            .path
    }

    deinit {
        stop()
    }

    public func start() {
        workerQueue.sync {
            refreshWatchers()
            initialScanCompleted = true
        }
    }

    public func startAsync() {
        workerQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.refreshWatchers()
            self.initialScanCompleted = true
        }
    }

    public func stop() {
        workerQueue.sync {
            pendingRescanWorkItem?.cancel()
            pendingRescanWorkItem = nil

            for workItem in pendingFileWorkItems.values {
                workItem.cancel()
            }
            pendingFileWorkItems.removeAll()

            for source in fileSources.values {
                source.cancel()
            }
            fileSources.removeAll()

            for descriptor in fileDescriptors.values where descriptor >= 0 {
                close(descriptor)
            }
            fileDescriptors.removeAll()

            for source in directorySources.values {
                source.cancel()
            }
            directorySources.removeAll()

            for descriptor in directoryDescriptors.values where descriptor >= 0 {
                close(descriptor)
            }
            directoryDescriptors.removeAll()

            trackedFiles.removeAll()
            initialScanCompleted = false
        }
    }

    private func scheduleRescan() {
        pendingRescanWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshWatchers()
        }
        pendingRescanWorkItem = workItem
        workerQueue.asyncAfter(deadline: .now() + config.rescanDebounceDelay, execute: workItem)
    }

    private func refreshWatchers() {
        refreshDirectoryWatchers()
        refreshFileWatchers()
    }

    private func refreshDirectoryWatchers() {
        let desiredDirectories = trackedDirectories()

        for path in directorySources.keys where desiredDirectories.contains(path) == false {
            directorySources[path]?.cancel()
            directorySources.removeValue(forKey: path)
            if let descriptor = directoryDescriptors.removeValue(forKey: path), descriptor >= 0 {
                close(descriptor)
            }
        }

        for path in desiredDirectories where directorySources[path] == nil {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete],
                queue: workerQueue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleRescan()
            }
            source.setCancelHandler { [weak self] in
                guard let self else {
                    return
                }
                if let descriptor = self.directoryDescriptors.removeValue(forKey: path), descriptor >= 0 {
                    close(descriptor)
                }
                self.directorySources.removeValue(forKey: path)
            }
            directoryDescriptors[path] = descriptor
            directorySources[path] = source
            source.resume()
        }
    }

    private func refreshFileWatchers() {
        let desiredFiles = trackedSessionFiles()

        for path in fileSources.keys where desiredFiles.contains(path) == false {
            pendingFileWorkItems[path]?.cancel()
            pendingFileWorkItems.removeValue(forKey: path)
            fileSources[path]?.cancel()
            fileSources.removeValue(forKey: path)
            trackedFiles.removeValue(forKey: path)
            if let descriptor = fileDescriptors.removeValue(forKey: path), descriptor >= 0 {
                close(descriptor)
            }
        }

        for path in desiredFiles {
            if trackedFiles[path] == nil {
                if initialScanCompleted {
                    try? initializeNewLiveFile(path: path)
                } else {
                    initializeExistingFile(path: path)
                }
            }

            guard fileSources[path] == nil else {
                continue
            }

            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete],
                queue: workerQueue
            )
            source.setEventHandler { [weak self] in
                guard let self else {
                    return
                }

                if source.data.contains(.rename) || source.data.contains(.delete) {
                    self.scheduleRescan()
                    return
                }

                self.config.onActivityPulse?()
                self.scheduleFileProcess(path: path)
            }
            source.setCancelHandler { [weak self] in
                guard let self else {
                    return
                }
                if let descriptor = self.fileDescriptors.removeValue(forKey: path), descriptor >= 0 {
                    close(descriptor)
                }
                self.fileSources.removeValue(forKey: path)
            }
            fileDescriptors[path] = descriptor
            fileSources[path] = source
            source.resume()
        }
    }

    private func initializeExistingFile(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        guard let sessionID = OpenclawSessionBackfillAdapter.sessionID(from: path),
              sessionID.isEmpty == false else {
            return
        }

        do {
            let metadata = try OpenclawSessionBackfillAdapter.scanSessionMetadata(
                from: path,
                config: OpenclawSessionBackfillAdapterConfig(sessionIDFallback: sessionID)
            )
            trackedFiles[path] = OpenclawTrackedSessionFile(
                sessionID: sessionID,
                offset: metadata.lastOffset,
                lineNumber: metadata.lastLineNumber,
                startedDuringLiveRuntime: false
            )
        } catch {
            return
        }
    }

    private func initializeNewLiveFile(path: String) throws {
        guard let sessionID = OpenclawSessionBackfillAdapter.sessionID(from: path),
              sessionID.isEmpty == false else {
            return
        }

        let delta = try OpenclawSessionBackfillAdapter.scanSessionDelta(
            from: path,
            startingAt: 0,
            startingLineNumber: 0,
            config: OpenclawSessionBackfillAdapterConfig(
                sessionIDFallback: sessionID,
                sourceMode: "openclaw_session_live",
                rawReferenceKind: "session_store_live",
                sessionOriginHint: .startedDuringLiveRuntime
            )
        )

        if delta.events.isEmpty == false {
            try append(events: delta.events)
        }

        trackedFiles[path] = OpenclawTrackedSessionFile(
            sessionID: sessionID,
            offset: delta.lastOffset,
            lineNumber: delta.lastLineNumber,
            startedDuringLiveRuntime: true
        )
    }

    private func scheduleFileProcess(path: String) {
        pendingFileWorkItems[path]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.processFileUpdate(path: path)
        }
        pendingFileWorkItems[path] = workItem
        workerQueue.asyncAfter(deadline: .now() + config.fileProcessDebounceDelay, execute: workItem)
    }

    private func processFileUpdate(path: String) {
        guard let trackedFile = trackedFiles[path] else {
            if initialScanCompleted {
                try? initializeNewLiveFile(path: path)
            } else {
                initializeExistingFile(path: path)
            }
            return
        }

        do {
            let delta = try OpenclawSessionBackfillAdapter.scanSessionDelta(
                from: path,
                startingAt: trackedFile.offset,
                startingLineNumber: trackedFile.lineNumber,
                config: OpenclawSessionBackfillAdapterConfig(
                    sessionIDFallback: trackedFile.sessionID,
                    sourceMode: "openclaw_session_live",
                    rawReferenceKind: "session_store_live",
                    sessionOriginHint: trackedFile.startedDuringLiveRuntime ? .startedDuringLiveRuntime : .unknown
                )
            )

            if delta.events.isEmpty == false {
                try append(events: delta.events)
            }

            trackedFiles[path] = OpenclawTrackedSessionFile(
                sessionID: delta.sessionID ?? trackedFile.sessionID,
                offset: delta.lastOffset,
                lineNumber: delta.lastLineNumber,
                startedDuringLiveRuntime: trackedFile.startedDuringLiveRuntime
            )
        } catch {
            return
        }
    }

    private func append(events: [ProviderUsageSampleEvent]) throws {
        guard events.isEmpty == false else {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let rendered = try events
            .map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"

        let outputURL = URL(fileURLWithPath: config.outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: config.outputPath) {
            let handle = try FileHandle(forWritingTo: outputURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(rendered.utf8))
        } else {
            try rendered.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    private func trackedDirectories() -> Set<String> {
        var directories: Set<String> = []

        if FileManager.default.fileExists(atPath: configurationRootPath) {
            directories.insert(configurationRootPath)
        }

        if FileManager.default.fileExists(atPath: config.sessionsRootPath) {
            directories.insert(config.sessionsRootPath)

            if let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: config.sessionsRootPath, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    if values?.isDirectory == true {
                        directories.insert(url.path)
                    }
                }
            }
        }

        return directories
    }

    private func trackedSessionFiles() -> Set<String> {
        guard FileManager.default.fileExists(atPath: config.sessionsRootPath) else {
            return []
        }

        var files: Set<String> = []
        if let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: config.sessionsRootPath, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                // Track only regular .jsonl files; skip checkpoint replays
                guard values?.isRegularFile == true,
                      url.pathExtension == "jsonl",
                      OpenclawSessionBackfillAdapter.sessionID(from: url.path) != nil else {
                    continue
                }
                files.insert(url.path)
            }
        }
        return files
    }
}
