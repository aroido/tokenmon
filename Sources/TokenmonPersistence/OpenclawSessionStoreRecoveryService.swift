import Foundation
import TokenmonDomain
import TokenmonProviders

public struct OpenclawSessionStoreRecoveryResult: Sendable {
    public let filesScanned: Int
    public let filesRecovered: Int
    public let samplesCreated: Int
    public let duplicatesSkipped: Int
    public let rejectedSamples: Int
    public let errorsCount: Int
}

public enum OpenclawSessionStoreRecoveryService {
    public static func run(
        databasePath: String,
        sessionsRootPath: String
    ) throws -> OpenclawSessionStoreRecoveryResult {
        guard FileManager.default.fileExists(atPath: sessionsRootPath) else {
            return OpenclawSessionStoreRecoveryResult(
                filesScanned: 0,
                filesRecovered: 0,
                samplesCreated: 0,
                duplicatesSkipped: 0,
                rejectedSamples: 0,
                errorsCount: 0
            )
        }

        let database = try TokenmonDatabaseManager(path: databasePath).open()
        let ingestService = UsageSampleIngestionService(databasePath: databasePath)

        var filesScanned = 0
        var filesRecovered = 0
        var samplesCreated = 0
        var duplicatesSkipped = 0
        var rejectedSamples = 0
        var errorsCount = 0

        for transcriptPath in sessionFiles(rootPath: sessionsRootPath) {
            filesScanned += 1

            do {
                let sessionID = OpenclawSessionBackfillAdapter.sessionID(from: transcriptPath)
                let sourceKey = sourceKey(transcriptPath: transcriptPath)
                var checkpoint = try IngestSourceCheckpointStore.loadOrCreate(
                    database: database,
                    sourceKey: sourceKey,
                    sourceKind: "session_store_recovery",
                    path: transcriptPath
                )
                checkpoint = try IngestSourceCheckpointStore.reconcileWithCurrentFile(
                    database: database,
                    checkpoint: checkpoint,
                    path: transcriptPath
                )

                let delta = try OpenclawSessionBackfillAdapter.scanSessionDelta(
                    from: transcriptPath,
                    startingAt: checkpoint.lastOffset,
                    startingLineNumber: checkpoint.lastLineNumber,
                    config: OpenclawSessionBackfillAdapterConfig(
                        sessionIDFallback: sessionID,
                        sourceMode: "openclaw_session_store_recovery",
                        rawReferenceKind: "session_store_recovery",
                        sessionOriginHint: .unknown
                    )
                )

                if delta.events.isEmpty == false {
                    let ingestResult = try ingestService.ingestProviderEvents(
                        database: database,
                        events: delta.events,
                        sourceKey: sourceKey,
                        sourcePath: transcriptPath,
                        sourceKind: "recovery_scan",
                        manageSourceCheckpoint: false
                    )

                    filesRecovered += 1
                    samplesCreated += ingestResult.usageSamplesCreated
                    duplicatesSkipped += ingestResult.duplicateEvents
                    rejectedSamples += ingestResult.rejectedEvents
                }

                try advanceCheckpointIfNeeded(
                    database: database,
                    checkpoint: checkpoint,
                    transcriptPath: transcriptPath,
                    result: delta
                )
            } catch {
                errorsCount += 1
            }
        }

        if filesScanned > 0 {
            try upsertRecoveryHealth(
                database: database,
                healthState: errorsCount == 0 ? "connected" : "degraded",
                message: errorsCount == 0
                    ? (
                        filesRecovered > 0
                            ? "OpenClaw startup recovery updated dashboard totals from local sessions"
                            : "OpenClaw startup recovery scanned local sessions with no new recoverable usage"
                    )
                    : "OpenClaw startup recovery skipped one or more session files due to read or parse errors"
            )
        }

        return OpenclawSessionStoreRecoveryResult(
            filesScanned: filesScanned,
            filesRecovered: filesRecovered,
            samplesCreated: samplesCreated,
            duplicatesSkipped: duplicatesSkipped,
            rejectedSamples: rejectedSamples,
            errorsCount: errorsCount
        )
    }

    private static func sessionFiles(rootPath: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: rootPath, isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(path: String, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  url.pathExtension == "jsonl",
                  OpenclawSessionBackfillAdapter.sessionID(from: url.path) != nil else {
                continue
            }
            files.append((url.path, values?.contentModificationDate ?? .distantPast))
        }

        return files
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt {
                    return lhs.modifiedAt < rhs.modifiedAt
                }
                return lhs.path < rhs.path
            }
            .map(\.path)
    }

    private static func sourceKey(transcriptPath: String) -> String {
        "recovery:openclaw:session_store:\(URL(fileURLWithPath: transcriptPath).path)"
    }

    private static func advanceCheckpointIfNeeded(
        database: SQLiteDatabase,
        checkpoint: IngestSourceCheckpoint,
        transcriptPath: String,
        result: OpenclawSessionBackfillDeltaResult
    ) throws {
        guard
            result.lastOffset != checkpoint.lastOffset
                || result.lastLineNumber != checkpoint.lastLineNumber
                || result.lastEventFingerprint != checkpoint.lastEventFingerprint
        else {
            return
        }

        try IngestSourceCheckpointStore.advance(
            database: database,
            sourceID: checkpoint.ingestSourceID,
            path: transcriptPath,
            offset: result.lastOffset,
            lineNumber: result.lastLineNumber,
            fingerprint: result.lastEventFingerprint
        )
    }

    private static func upsertRecoveryHealth(
        database: SQLiteDatabase,
        healthState: String,
        message: String
    ) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO provider_health (
                provider_code,
                source_mode,
                health_state,
                message,
                last_success_at,
                last_error_at,
                last_error_code,
                last_error_summary,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
            ON CONFLICT(provider_code, source_mode) DO UPDATE SET
                health_state = excluded.health_state,
                message = excluded.message,
                last_success_at = excluded.last_success_at,
                last_error_at = NULL,
                last_error_code = NULL,
                last_error_summary = NULL,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(ProviderCode.openclaw.rawValue),
                .text("openclaw_session_store_recovery"),
                .text(healthState),
                .text(message),
                .text(now),
                .text(now),
            ]
        )
    }
}
