import Foundation
import TokenmonDomain

public struct BackfillRunSummary: Equatable, Sendable {
    public let backfillRunID: Int64
    public let provider: ProviderCode
    public let mode: String
    public let status: String
    public let startedAt: String
    public let completedAt: String?
    public let samplesExamined: Int64
    public let samplesCreated: Int64
    public let duplicatesSkipped: Int64
    public let errorsCount: Int64
    public let summaryJSON: String?

    public init(
        backfillRunID: Int64,
        provider: ProviderCode,
        mode: String,
        status: String,
        startedAt: String,
        completedAt: String?,
        samplesExamined: Int64,
        samplesCreated: Int64,
        duplicatesSkipped: Int64,
        errorsCount: Int64,
        summaryJSON: String?
    ) {
        self.backfillRunID = backfillRunID
        self.provider = provider
        self.mode = mode
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.samplesExamined = samplesExamined
        self.samplesCreated = samplesCreated
        self.duplicatesSkipped = duplicatesSkipped
        self.errorsCount = errorsCount
        self.summaryJSON = summaryJSON
    }
}

public struct BackfillRunResult: Sendable {
    public let backfillRunID: Int64
    public let provider: ProviderCode
    public let mode: String
    public let status: String
    public let summaryJSON: String
}

public enum BackfillRunStore {
    public static func startBackfillRun(
        database: SQLiteDatabase,
        provider: ProviderCode,
        providerSessionID: String?,
        mode: String
    ) throws -> Int64 {
        let startedAt = ISO8601DateFormatter().string(from: Date())
        let sessionRowID = try lookupProviderSessionRowID(
            database: database,
            provider: provider,
            providerSessionID: providerSessionID
        )

        try database.execute(
            """
            INSERT INTO backfill_runs (
                provider_code,
                provider_session_row_id,
                mode,
                started_at,
                completed_at,
                status,
                samples_examined,
                samples_created,
                duplicates_skipped,
                errors_count,
                summary_json
            ) VALUES (?, ?, ?, ?, NULL, 'running', 0, 0, 0, 0, NULL);
            """,
            bindings: [
                .text(provider.rawValue),
                sessionRowID.map(SQLiteValue.integer) ?? .null,
                .text(mode),
                .text(startedAt),
            ]
        )

        return database.lastInsertRowID()
    }

    public static func completeBackfillRun(
        database: SQLiteDatabase,
        backfillRunID: Int64,
        provider: ProviderCode,
        mode: String,
        status: String,
        samplesExamined: Int64,
        samplesCreated: Int64,
        duplicatesSkipped: Int64,
        errorsCount: Int64,
        summaryJSON: String
    ) throws -> BackfillRunResult {
        let completedAt = ISO8601DateFormatter().string(from: Date())

        try database.execute(
            """
            UPDATE backfill_runs
            SET completed_at = ?,
                status = ?,
                samples_examined = ?,
                samples_created = ?,
                duplicates_skipped = ?,
                errors_count = ?,
                summary_json = ?
            WHERE backfill_run_id = ?;
            """,
            bindings: [
                .text(completedAt),
                .text(status),
                .integer(samplesExamined),
                .integer(samplesCreated),
                .integer(duplicatesSkipped),
                .integer(errorsCount),
                .text(summaryJSON),
                .integer(backfillRunID),
            ]
        )

        return BackfillRunResult(
            backfillRunID: backfillRunID,
            provider: provider,
            mode: mode,
            status: status,
            summaryJSON: summaryJSON
        )
    }

    public static func recordUnsupportedTranscriptBackfill(
        databasePath: String,
        provider: ProviderCode,
        providerSessionID: String?,
        transcriptPath: String
    ) throws -> BackfillRunResult {
        let database = try TokenmonDatabaseManager(path: databasePath).open()
        return try recordUnsupportedTranscriptBackfill(
            database: database,
            provider: provider,
            providerSessionID: providerSessionID,
            transcriptPath: transcriptPath
        )
    }

    public static func recordUnsupportedTranscriptBackfill(
        database: SQLiteDatabase,
        provider: ProviderCode,
        providerSessionID: String?,
        transcriptPath: String
    ) throws -> BackfillRunResult {
        let backfillRunID = try startBackfillRun(
            database: database,
            provider: provider,
            providerSessionID: providerSessionID,
            mode: "transcript_backfill"
        )
        try DomainEventStore.persist(
            database: database,
            envelope: TokenmonDomainEventRegistry.backfillStarted(
                runID: backfillRunID,
                provider: provider,
                sessionID: providerSessionID,
                reason: "Transcript backfill is not implemented for this provider mode"
            )
        )

        let reason = FileManager.default.fileExists(atPath: transcriptPath)
            ? "transcript-assisted backfill is not implemented yet for this mode"
            : "transcript path does not exist and transcript-assisted backfill is not implemented yet"

        let summaryJSON = """
        {"provider":"\(provider.rawValue)","mode":"transcript_backfill","transcript_path":"\(transcriptPath)","reason":"\(reason)"}
        """

        let result = try completeBackfillRun(
            database: database,
            backfillRunID: backfillRunID,
            provider: provider,
            mode: "transcript_backfill",
            status: "failed",
            samplesExamined: 0,
            samplesCreated: 0,
            duplicatesSkipped: 0,
            errorsCount: 1,
            summaryJSON: summaryJSON
        )
        try DomainEventStore.persist(
            database: database,
            envelope: TokenmonDomainEventRegistry.backfillCompleted(
                runID: backfillRunID,
                provider: provider,
                sessionID: providerSessionID,
                samplesExamined: 0,
                samplesCreated: 0,
                duplicatesSkipped: 0,
                errorsCount: 1
            )
        )
        try upsertUnsupportedBackfillHealth(
            database: database,
            provider: provider,
            reason: reason
        )
        return result
    }

    public static func latestBackfillRunSummary(
        database: SQLiteDatabase,
        provider: ProviderCode
    ) throws -> BackfillRunSummary? {
        try database.fetchOne(
            """
            SELECT backfill_run_id,
                   provider_code,
                   mode,
                   status,
                   started_at,
                   completed_at,
                   samples_examined,
                   samples_created,
                   duplicates_skipped,
                   errors_count,
                   summary_json
            FROM backfill_runs
            WHERE provider_code = ?
            ORDER BY backfill_run_id DESC
            LIMIT 1;
            """,
            bindings: [.text(provider.rawValue)]
        ) { statement in
            BackfillRunSummary(
                backfillRunID: SQLiteDatabase.columnInt64(statement, index: 0),
                provider: provider,
                mode: SQLiteDatabase.columnText(statement, index: 2),
                status: SQLiteDatabase.columnText(statement, index: 3),
                startedAt: SQLiteDatabase.columnText(statement, index: 4),
                completedAt: SQLiteDatabase.columnOptionalText(statement, index: 5),
                samplesExamined: SQLiteDatabase.columnInt64(statement, index: 6),
                samplesCreated: SQLiteDatabase.columnInt64(statement, index: 7),
                duplicatesSkipped: SQLiteDatabase.columnInt64(statement, index: 8),
                errorsCount: SQLiteDatabase.columnInt64(statement, index: 9),
                summaryJSON: SQLiteDatabase.columnOptionalText(statement, index: 10)
            )
        }
    }

    public static func recentBackfillRunSummaries(
        database: SQLiteDatabase,
        limit: Int = 20
    ) throws -> [BackfillRunSummary] {
        guard limit > 0 else {
            return []
        }

        return try database.fetchAll(
            """
            SELECT backfill_run_id,
                   provider_code,
                   mode,
                   status,
                   started_at,
                   completed_at,
                   samples_examined,
                   samples_created,
                   duplicates_skipped,
                   errors_count,
                   summary_json
            FROM backfill_runs
            ORDER BY backfill_run_id DESC
            LIMIT ?;
            """,
            bindings: [.integer(Int64(limit))]
        ) { statement in
            let providerRawValue = SQLiteDatabase.columnText(statement, index: 1)
            guard let provider = ProviderCode(rawValue: providerRawValue) else {
                throw SQLiteError.statementFailed(
                    message: "invalid provider_code \(providerRawValue)",
                    sql: "SELECT provider_code FROM backfill_runs ..."
                )
            }

            return BackfillRunSummary(
                backfillRunID: SQLiteDatabase.columnInt64(statement, index: 0),
                provider: provider,
                mode: SQLiteDatabase.columnText(statement, index: 2),
                status: SQLiteDatabase.columnText(statement, index: 3),
                startedAt: SQLiteDatabase.columnText(statement, index: 4),
                completedAt: SQLiteDatabase.columnOptionalText(statement, index: 5),
                samplesExamined: SQLiteDatabase.columnInt64(statement, index: 6),
                samplesCreated: SQLiteDatabase.columnInt64(statement, index: 7),
                duplicatesSkipped: SQLiteDatabase.columnInt64(statement, index: 8),
                errorsCount: SQLiteDatabase.columnInt64(statement, index: 9),
                summaryJSON: SQLiteDatabase.columnOptionalText(statement, index: 10)
            )
        }
    }

    private static func lookupProviderSessionRowID(
        database: SQLiteDatabase,
        provider: ProviderCode,
        providerSessionID: String?
    ) throws -> Int64? {
        guard let providerSessionID else {
            return nil
        }

        return try database.fetchOne(
            """
            SELECT provider_session_row_id
            FROM provider_sessions
            WHERE provider_code = ? AND provider_session_id = ?
            LIMIT 1;
            """,
            bindings: [.text(provider.rawValue), .text(providerSessionID)]
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }
    }

    private static func upsertUnsupportedBackfillHealth(
        database: SQLiteDatabase,
        provider: ProviderCode,
        reason: String
    ) throws {
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        let message: String
        switch provider {
        case .claude:
            message = "Claude transcript backfill mode is unsupported in this path"
        case .codex:
            message = "Codex transcript backfill is unsupported for the current configuration"
        case .gemini:
            message = "Gemini transcript backfill is unsupported for the current configuration"
        case .cursor:
            message = "Cursor transcript backfill is unsupported for the current configuration"
        case .openclaw:
            message = "OpenClaw transcript backfill is unsupported for the current configuration"
        }

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
            ) VALUES (?, ?, 'unsupported', ?, NULL, ?, NULL, ?, ?)
            ON CONFLICT(provider_code, source_mode) DO UPDATE SET
                health_state = excluded.health_state,
                message = excluded.message,
                last_error_at = excluded.last_error_at,
                last_error_code = NULL,
                last_error_summary = excluded.last_error_summary,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(provider.rawValue),
                .text("\(provider.rawValue)_transcript_backfill"),
                .text(message),
                .text(updatedAt),
                .text(reason),
                .text(updatedAt),
            ]
        )
    }
}

public extension TokenmonDatabaseManager {
    func recentBackfillRunSummaries(limit: Int = 20, database providedDatabase: SQLiteDatabase? = nil) throws -> [BackfillRunSummary] {
        let database = try providedDatabase ?? open()
        return try BackfillRunStore.recentBackfillRunSummaries(database: database, limit: limit)
    }
}
