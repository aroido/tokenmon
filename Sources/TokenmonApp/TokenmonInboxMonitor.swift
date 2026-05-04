import Darwin
import Foundation
import TokenmonDomain
import TokenmonPersistence

final class TokenmonInboxMonitor: @unchecked Sendable {
    private let databasePath: String
    private let ingestService: UsageSampleIngestionService
    private let workerQueue = DispatchQueue(label: "TokenmonApp.InboxMonitor")
    private let scanDebounceDelay: DispatchTimeInterval
    private let transcriptBackfillDebounceDelay: DispatchTimeInterval

    private var directoryFileDescriptor: CInt = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: CInt] = [:]
    private var transcriptSources: [String: DispatchSourceFileSystemObject] = [:]
    private var transcriptDescriptors: [String: CInt] = [:]
    private var transcriptSessionIDs: [String: String] = [:]
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingTranscriptWorkItems: [String: DispatchWorkItem] = [:]

    init(
        databasePath: String,
        scanDebounceDelay: DispatchTimeInterval = .milliseconds(250),
        transcriptBackfillDebounceDelay: DispatchTimeInterval = .milliseconds(900)
    ) {
        self.databasePath = databasePath
        ingestService = UsageSampleIngestionService(databasePath: databasePath)
        self.scanDebounceDelay = scanDebounceDelay
        self.transcriptBackfillDebounceDelay = transcriptBackfillDebounceDelay
    }

    deinit {
        shutdown()
    }

    func stop() {
        workerQueue.sync {
            shutdown()
        }
    }

    private func shutdown() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        for workItem in pendingTranscriptWorkItems.values {
            workItem.cancel()
        }
        pendingTranscriptWorkItems.removeAll()
        directorySource?.cancel()
        directorySource = nil
        for source in fileSources.values {
            source.cancel()
        }
        fileSources.removeAll()
        for source in transcriptSources.values {
            source.cancel()
        }
        transcriptSources.removeAll()
        if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
            directoryFileDescriptor = -1
        }
        for descriptor in fileDescriptors.values where descriptor >= 0 {
            close(descriptor)
        }
        fileDescriptors.removeAll()
        for descriptor in transcriptDescriptors.values where descriptor >= 0 {
            close(descriptor)
        }
        transcriptDescriptors.removeAll()
        transcriptSessionIDs.removeAll()
    }

    func start(onRefresh: @escaping @MainActor () -> Void) {
        workerQueue.sync { [weak self] in
            self?.startWatching(onRefresh: onRefresh)
        }
    }

    func startAsync(onRefresh: @escaping @MainActor () -> Void) {
        workerQueue.async { [weak self] in
            self?.startWatching(onRefresh: onRefresh)
        }
    }

    func performInitialScan() {
        performScan(onRefresh: {})
    }

    func performInitialScanAsync(onRefresh: @escaping @MainActor () -> Void) {
        workerQueue.async { [weak self] in
            self?.performScan(onRefresh: onRefresh)
        }
    }

    private func performScan(onRefresh: @escaping @MainActor () -> Void) {
        logInboxMonitor(event: "perform_scan_started", metadata: [:])
        let inboxPaths = ensureInboxFilesExist()

        for inboxPath in inboxPaths where FileManager.default.fileExists(atPath: inboxPath) {
            let filename = URL(fileURLWithPath: inboxPath).lastPathComponent
            do {
                let result = try ingestService.ingestInboxFile(at: inboxPath)
                logInboxMonitor(
                    event: "ingest_inbox_file_completed",
                    metadata: [
                        "inbox": filename,
                        "accepted": "\(result.acceptedEvents)",
                        "duplicates": "\(result.duplicateEvents)",
                        "rejected": "\(result.rejectedEvents)",
                        "usage_samples": "\(result.usageSamplesCreated)",
                        "last_offset": "\(result.lastOffset)",
                    ]
                )
            } catch {
                logInboxMonitor(
                    event: "ingest_inbox_file_failed",
                    metadata: [
                        "inbox": filename,
                        "error": String(describing: error),
                    ]
                )
                continue
            }
        }

        refreshFileWatchers(onRefresh: onRefresh)
        refreshTranscriptWatchers(onRefresh: onRefresh)
        processPendingBackfillRequests()

        Task { @MainActor in
            onRefresh()
        }
    }

    private func logInboxMonitor(event: String, metadata: [String: String]) {
        let supportDirectoryPath = TokenmonDatabaseManager.supportDirectory(forDatabasePath: databasePath)
        TokenmonAppBehaviorLogger.debug(
            category: "inbox_monitor",
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    private func processPendingBackfillRequests() {
        let requests = (try? ProviderBackfillRequestQueue.pendingRequests(databasePath: databasePath)) ?? []

        for pendingRequest in requests {
            switch pendingRequest.request.provider {
            case .claude:
                do {
                    _ = try ClaudeTranscriptBackfillService.run(
                        databasePath: databasePath,
                        providerSessionID: pendingRequest.request.providerSessionID,
                        transcriptPath: pendingRequest.request.transcriptPath
                    )
                } catch {
                    ProviderBackfillRequestQueue.removeRequest(at: pendingRequest.filePath)
                    continue
                }
            case .codex:
                do {
                    _ = try CodexTranscriptBackfillService.run(
                        databasePath: databasePath,
                        providerSessionID: pendingRequest.request.providerSessionID,
                        transcriptPath: pendingRequest.request.transcriptPath
                    )
                } catch {
                    ProviderBackfillRequestQueue.removeRequest(at: pendingRequest.filePath)
                    continue
                }
            case .gemini:
                ProviderBackfillRequestQueue.removeRequest(at: pendingRequest.filePath)
                continue
            case .cursor:
                ProviderBackfillRequestQueue.removeRequest(at: pendingRequest.filePath)
                continue
            case .openclaw:
                ProviderBackfillRequestQueue.removeRequest(at: pendingRequest.filePath)
                continue
            }

            ProviderBackfillRequestQueue.removeRequest(at: pendingRequest.filePath)
        }
    }

    private func startWatching(onRefresh: @escaping @MainActor () -> Void) {
        guard directorySource == nil else {
            return
        }

        let inboxDirectory = TokenmonDatabaseManager.inboxDirectory(forDatabasePath: databasePath)
        do {
            try FileManager.default.createDirectory(
                atPath: inboxDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        let descriptor = open(inboxDirectory, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        directoryFileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: workerQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let rawMask = source.data.rawValue
            self.logInboxMonitor(
                event: "directory_event",
                metadata: ["mask": String(rawMask)]
            )
            self.scheduleScan(onRefresh: onRefresh)
        }
        source.setCancelHandler { [weak self] in
            guard let self else {
                return
            }
            if self.directoryFileDescriptor >= 0 {
                close(self.directoryFileDescriptor)
                self.directoryFileDescriptor = -1
            }
        }
        directorySource = source
        source.resume()

        _ = ensureInboxFilesExist()
        refreshFileWatchers(onRefresh: onRefresh)
        refreshTranscriptWatchers(onRefresh: onRefresh)
    }

    private func scheduleScan(onRefresh: @escaping @MainActor () -> Void) {
        let hadPending = pendingWorkItem != nil
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performScan(onRefresh: onRefresh)
        }
        pendingWorkItem = workItem
        workerQueue.asyncAfter(deadline: .now() + scanDebounceDelay, execute: workItem)
        logInboxMonitor(
            event: "scan_scheduled",
            metadata: ["cancelled_previous": hadPending ? "yes" : "no"]
        )
    }

    private func refreshFileWatchers(onRefresh: @escaping @MainActor () -> Void) {
        let inboxPaths = ensureInboxFilesExist()
        let existingPaths = Set(inboxPaths.filter { FileManager.default.fileExists(atPath: $0) })

        for path in fileSources.keys where existingPaths.contains(path) == false {
            fileSources[path]?.cancel()
            fileSources.removeValue(forKey: path)

            if let descriptor = fileDescriptors.removeValue(forKey: path), descriptor >= 0 {
                close(descriptor)
            }
        }

        for path in existingPaths where fileSources[path] == nil {
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

                let rawMask = source.data.rawValue
                self.logInboxMonitor(
                    event: "file_event",
                    metadata: [
                        "file": URL(fileURLWithPath: path).lastPathComponent,
                        "mask": String(rawMask),
                    ]
                )

                if source.data.contains(.rename) || source.data.contains(.delete) {
                    self.refreshFileWatchers(onRefresh: onRefresh)
                }
                self.scheduleScan(onRefresh: onRefresh)
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

    @discardableResult
    private func ensureInboxFilesExist() -> [String] {
        let inboxPaths = ProviderCode.allCases.map {
            TokenmonDatabaseManager.inboxPath(provider: $0, databasePath: databasePath)
        }

        for inboxPath in inboxPaths where FileManager.default.fileExists(atPath: inboxPath) == false {
            let url = URL(fileURLWithPath: inboxPath)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: inboxPath, contents: nil)
        }

        return inboxPaths
    }

    private func refreshTranscriptWatchers(onRefresh: @escaping @MainActor () -> Void) {
        let activeSessions = activeCodexTranscriptSessions()
        let existingPaths = Set(activeSessions.keys.filter { FileManager.default.fileExists(atPath: $0) })

        for path in transcriptSources.keys where existingPaths.contains(path) == false {
            pendingTranscriptWorkItems[path]?.cancel()
            pendingTranscriptWorkItems.removeValue(forKey: path)
            transcriptSources[path]?.cancel()
            transcriptSources.removeValue(forKey: path)
            transcriptSessionIDs.removeValue(forKey: path)

            if let descriptor = transcriptDescriptors.removeValue(forKey: path), descriptor >= 0 {
                close(descriptor)
            }
        }

        for path in existingPaths where transcriptSources[path] == nil {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0, let sessionID = activeSessions[path] else {
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
                    self.refreshTranscriptWatchers(onRefresh: onRefresh)
                    return
                }

                self.scheduleTranscriptBackfill(
                    sessionID: sessionID,
                    transcriptPath: path,
                    onRefresh: onRefresh
                )
            }
            source.setCancelHandler { [weak self] in
                guard let self else {
                    return
                }
                if let descriptor = self.transcriptDescriptors.removeValue(forKey: path), descriptor >= 0 {
                    close(descriptor)
                }
                self.transcriptSources.removeValue(forKey: path)
                self.transcriptSessionIDs.removeValue(forKey: path)
                self.pendingTranscriptWorkItems[path]?.cancel()
                self.pendingTranscriptWorkItems.removeValue(forKey: path)
            }

            transcriptDescriptors[path] = descriptor
            transcriptSources[path] = source
            transcriptSessionIDs[path] = sessionID
            source.resume()
        }
    }

    private func scheduleTranscriptBackfill(
        sessionID: String,
        transcriptPath: String,
        onRefresh: @escaping @MainActor () -> Void
    ) {
        pendingTranscriptWorkItems[transcriptPath]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runTranscriptBackfill(
                sessionID: sessionID,
                transcriptPath: transcriptPath,
                onRefresh: onRefresh
            )
        }
        pendingTranscriptWorkItems[transcriptPath] = workItem
        workerQueue.asyncAfter(deadline: .now() + transcriptBackfillDebounceDelay, execute: workItem)
    }

    private func runTranscriptBackfill(
        sessionID: String,
        transcriptPath: String,
        onRefresh: @escaping @MainActor () -> Void
    ) {
        guard transcriptContainsTokenCount(transcriptPath) else {
            return
        }

        do {
            _ = try CodexTranscriptBackfillService.run(
                databasePath: databasePath,
                providerSessionID: sessionID,
                transcriptPath: transcriptPath
            )
        } catch {
            return
        }

        Task { @MainActor in
            onRefresh()
        }
    }

    private func activeCodexTranscriptSessions() -> [String: String] {
        do {
            let database = try TokenmonDatabaseManager(path: databasePath).open()
            let rows: [(String, String)] = try database.fetchAll(
                """
                SELECT transcript_path, provider_session_id
                FROM provider_sessions
                WHERE provider_code = ?
                  AND session_state = 'active'
                  AND transcript_path IS NOT NULL
                  AND transcript_path != '';
                """,
                bindings: [.text(ProviderCode.codex.rawValue)],
                map: { statement in
                    (
                        SQLiteDatabase.columnText(statement, index: 0),
                        SQLiteDatabase.columnText(statement, index: 1)
                    )
                }
            )

            return Dictionary(uniqueKeysWithValues: rows)
        } catch {
            return [:]
        }
    }

    private func transcriptContainsTokenCount(_ transcriptPath: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: transcriptPath), options: [.mappedIfSafe]) else {
            return false
        }

        let windowSize = min(data.count, 32_768)
        let window = data.suffix(windowSize)
        let renderedWindow = String(decoding: window, as: UTF8.self)
        return renderedWindow.contains("\"token_count\"")
    }
}
