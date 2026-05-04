import Foundation
import TokenmonDomain

public struct ProviderHealthSummary: Equatable, Sendable {
    public let provider: ProviderCode
    public let sourceMode: String?
    public let healthState: String
    public let supportLevel: String
    public let reliabilityLabel: String
    public let message: String
    public let offlineDashboardRecovery: String
    public let liveGameplayArmed: Bool
    public let diagnosticFacts: [String: String]
    public let lastSuccessAt: String?
    public let lastErrorAt: String?
    public let lastErrorSummary: String?
    public let lastObservedAt: String?
    public let lastBackfillMode: String?
    public let lastBackfillStatus: String?
    public let lastBackfillCompletedAt: String?
    public let lastBackfillSummary: String?
}

public extension TokenmonDatabaseManager {
    func providerHealthSummaries(database providedDatabase: SQLiteDatabase? = nil) throws -> [ProviderHealthSummary] {
        let database = try providedDatabase ?? open()
        let hasLiveGameplayBoundary = try liveGameplayStartedAt(database: database) != nil

        return try ProviderCode.allCases.map { provider in
            let resolvedSourceMode = try latestSourceMode(for: provider, database: database)
            let persistedRow = try persistedHealth(
                for: provider,
                sourceMode: resolvedSourceMode,
                database: database
            )
            let observedAt = try latestObservedAt(for: provider, sourceMode: resolvedSourceMode, database: database)
            let inferred = inferHealth(
                provider: provider,
                sourceMode: resolvedSourceMode,
                persistedHealthState: persistedRow?.healthState,
                persistedMessage: persistedRow?.message,
                lastSuccessAt: persistedRow?.lastSuccessAt,
                lastErrorAt: persistedRow?.lastErrorAt,
                lastErrorSummary: persistedRow?.lastErrorSummary,
                lastObservedAt: observedAt
            )
            let latestBackfill = try BackfillRunStore.latestBackfillRunSummary(
                database: database,
                provider: provider
            )

            return ProviderHealthSummary(
                provider: provider,
                sourceMode: resolvedSourceMode ?? inferred.sourceMode,
                healthState: inferred.healthState,
                supportLevel: provider.defaultSupportLevel,
                reliabilityLabel: reliabilityLabel(
                    provider: provider,
                    sourceMode: resolvedSourceMode ?? inferred.sourceMode,
                    healthState: inferred.healthState
                ),
                message: inferred.message,
                offlineDashboardRecovery: offlineDashboardRecoveryPolicy(for: provider),
                liveGameplayArmed: liveGameplayArmed(
                    provider: provider,
                    sourceMode: resolvedSourceMode ?? inferred.sourceMode,
                    healthState: inferred.healthState,
                    hasLiveGameplayBoundary: hasLiveGameplayBoundary
                ),
                diagnosticFacts: try providerDiagnosticFacts(
                    provider: provider,
                    database: database
                ),
                lastSuccessAt: persistedRow?.lastSuccessAt ?? observedAt,
                lastErrorAt: persistedRow?.lastErrorAt,
                lastErrorSummary: persistedRow?.lastErrorSummary,
                lastObservedAt: observedAt,
                lastBackfillMode: latestBackfill?.mode,
                lastBackfillStatus: latestBackfill?.status,
                lastBackfillCompletedAt: latestBackfill?.completedAt,
                lastBackfillSummary: latestBackfill?.summaryJSON
            )
        }
    }

    private struct PersistedHealthRow {
        let healthState: String?
        let message: String?
        let lastSuccessAt: String?
        let lastErrorAt: String?
        let lastErrorSummary: String?
    }

    private func persistedHealth(
        for provider: ProviderCode,
        sourceMode: String?,
        database: SQLiteDatabase
    ) throws -> PersistedHealthRow? {
        if let sourceMode {
            return try database.fetchOne(
                """
                SELECT health_state,
                       message,
                       last_success_at,
                       last_error_at,
                       last_error_summary
                FROM provider_health
                WHERE provider_code = ? AND source_mode = ?
                LIMIT 1;
                """,
                bindings: [.text(provider.rawValue), .text(sourceMode)]
            ) { statement in
                PersistedHealthRow(
                    healthState: SQLiteDatabase.columnOptionalText(statement, index: 0),
                    message: SQLiteDatabase.columnOptionalText(statement, index: 1),
                    lastSuccessAt: SQLiteDatabase.columnOptionalText(statement, index: 2),
                    lastErrorAt: SQLiteDatabase.columnOptionalText(statement, index: 3),
                    lastErrorSummary: SQLiteDatabase.columnOptionalText(statement, index: 4)
                )
            }
        }

        return try database.fetchOne(
            """
            SELECT health_state,
                   message,
                   last_success_at,
                   last_error_at,
                   last_error_summary
            FROM provider_health
            WHERE provider_code = ?
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bindings: [.text(provider.rawValue)]
        ) { statement in
            PersistedHealthRow(
                healthState: SQLiteDatabase.columnOptionalText(statement, index: 0),
                message: SQLiteDatabase.columnOptionalText(statement, index: 1),
                lastSuccessAt: SQLiteDatabase.columnOptionalText(statement, index: 2),
                lastErrorAt: SQLiteDatabase.columnOptionalText(statement, index: 3),
                lastErrorSummary: SQLiteDatabase.columnOptionalText(statement, index: 4)
            )
        }
    }

    private func latestObservedAt(
        for provider: ProviderCode,
        sourceMode: String?,
        database: SQLiteDatabase
    ) throws -> String? {
        if provider == .cursor {
            if let sourceMode {
                let observedAtForSource = try database.fetchOne(
                    """
                    SELECT observed_at
                    FROM account_usage_samples
                    WHERE provider_code = ? AND source_mode = ?
                    ORDER BY observed_at DESC, account_usage_sample_id DESC
                    LIMIT 1;
                    """,
                    bindings: [.text(provider.rawValue), .text(sourceMode)]
                ) { statement in
                    SQLiteDatabase.columnText(statement, index: 0)
                }
                if let observedAtForSource {
                    return observedAtForSource
                }
            }

            let latestAccountObservedAt = try database.fetchOne(
                """
                SELECT observed_at
                FROM account_usage_samples
                WHERE provider_code = ?
                ORDER BY observed_at DESC, account_usage_sample_id DESC
                LIMIT 1;
                """,
                bindings: [.text(provider.rawValue)]
            ) { statement in
                SQLiteDatabase.columnText(statement, index: 0)
            }
            if let latestAccountObservedAt {
                return latestAccountObservedAt
            }
            return nil
        }

        if let sourceMode {
            return try database.fetchOne(
                """
                SELECT observed_at
                FROM provider_ingest_events
                WHERE provider_code = ? AND source_mode = ?
                ORDER BY provider_ingest_event_id DESC
                LIMIT 1;
                """,
                bindings: [.text(provider.rawValue), .text(sourceMode)]
            ) { statement in
                SQLiteDatabase.columnText(statement, index: 0)
            }
        }

        return try database.fetchOne(
            """
            SELECT observed_at
            FROM provider_ingest_events
            WHERE provider_code = ?
            ORDER BY provider_ingest_event_id DESC
            LIMIT 1;
            """,
            bindings: [.text(provider.rawValue)]
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
    }

    private func latestSourceMode(
        for provider: ProviderCode,
        database: SQLiteDatabase
    ) throws -> String? {
        if provider == .codex {
            return try preferredCodexSourceMode(database: database)
        }
        if provider == .cursor {
            let accountSourceMode = try database.fetchOne(
                """
                SELECT source_mode
                FROM account_usage_samples
                WHERE provider_code = 'cursor'
                ORDER BY observed_at DESC, account_usage_sample_id DESC
                LIMIT 1;
                """
            ) { statement in
                SQLiteDatabase.columnText(statement, index: 0)
            }
            if let accountSourceMode {
                return accountSourceMode
            }
            return nil
        }

        return try database.fetchOne(
            """
            SELECT source_mode
            FROM provider_ingest_events
            WHERE provider_code = ?
            ORDER BY provider_ingest_event_id DESC
            LIMIT 1;
            """,
            bindings: [.text(provider.rawValue)]
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        } ?? database.fetchOne(
            """
            SELECT source_mode
            FROM provider_health
            WHERE provider_code = ?
              AND source_mode IS NOT NULL
            ORDER BY updated_at DESC
            LIMIT 1;
            """,
            bindings: [.text(provider.rawValue)]
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
    }

    private func preferredCodexSourceMode(database: SQLiteDatabase) throws -> String? {
        let sql = """
        SELECT source_mode
        FROM (
            SELECT source_mode,
                   provider_ingest_event_id AS sort_key
            FROM provider_ingest_events
            WHERE provider_code = 'codex'
            UNION ALL
            SELECT source_mode,
                   0 AS sort_key
            FROM provider_health
            WHERE provider_code = 'codex' AND source_mode IS NOT NULL
        )
        ORDER BY
            CASE source_mode
                WHEN 'codex_exec_json' THEN 0
                WHEN 'codex_session_store_live' THEN 1
                WHEN 'codex_session_store_recovery' THEN 2
                WHEN 'codex_interactive_hook_assisted' THEN 3
                WHEN 'codex_transcript_backfill' THEN 4
                WHEN 'codex_interactive_observer' THEN 5
                ELSE 99
            END ASC,
            sort_key DESC
        LIMIT 1;
        """

        return try database.fetchOne(sql) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
    }

    private func inferHealth(
        provider: ProviderCode,
        sourceMode: String?,
        persistedHealthState: String?,
        persistedMessage: String?,
        lastSuccessAt: String?,
        lastErrorAt: String?,
        lastErrorSummary: String?,
        lastObservedAt: String?
    ) -> (sourceMode: String?, healthState: String, message: String) {
        if let persistedHealthState, let persistedMessage {
            return (sourceMode, persistedHealthState, persistedMessage)
        }

        if provider == .codex,
           sourceMode == "codex_session_store_recovery",
           let lastObservedAt
        {
            return (
                sourceMode,
                "connected",
                "Codex startup recovery updated dashboard totals at \(lastObservedAt); gameplay still waits for live monitoring"
            )
        }

        if provider == .claude,
           sourceMode == "claude_transcript_backfill",
           let lastObservedAt
        {
            return (
                sourceMode,
                "connected",
                "Claude transcript recovery updated dashboard totals at \(lastObservedAt); gameplay still waits for live transcript, status line, or OTel usage"
            )
        }

        if provider == .claude,
           sourceMode == "claude_transcript_live",
           let lastObservedAt
        {
            return (
                sourceMode,
                "active",
                "Claude passive transcript monitoring observed usage at \(lastObservedAt)"
            )
        }

        if provider == .claude,
           sourceMode == "claude_otel_api_request_live",
           let lastObservedAt
        {
            return (
                sourceMode,
                "active",
                "Claude ingest active via OTel api_request at \(lastObservedAt)"
            )
        }

        if provider == .cursor,
           let sourceMode,
           let lastObservedAt,
           sourceMode.hasPrefix("cursor_")
        {
            return (
                sourceMode,
                "connected",
                "Cursor stats-only accounting imported at \(lastObservedAt); Cursor usage never drives gameplay"
            )
        }

        if let sourceMode, let lastObservedAt {
            return (
                sourceMode,
                "active",
                "\(provider.displayName) ingest active via \(sourceMode) at \(lastObservedAt)"
            )
        }

        if let lastObservedAt {
            return (
                sourceMode,
                "connected",
                "\(provider.displayName) has prior ingest activity at \(lastObservedAt)"
            )
        }

        if let lastErrorAt {
            return (
                sourceMode,
                "degraded",
                lastErrorSummary ?? "\(provider.displayName) last error at \(lastErrorAt)"
            )
        }

        switch provider {
        case .claude:
            return (
                sourceMode ?? "claude_transcript_live",
                "connected",
                "Claude passive transcript monitoring is ready; status line settings are left unchanged"
            )
        case .codex:
            return (
                sourceMode ?? "codex_session_store_live",
                "missing_configuration",
                "Codex is not detected or has no session activity yet"
            )
        case .gemini:
            return (
                sourceMode ?? "gemini_otel_receiver",
                "missing_configuration",
                "Gemini observation is not configured yet"
            )
        case .cursor:
            return (
                sourceMode ?? "cursor_usage_export_api",
                "missing_configuration",
                "Cursor usage export has not been imported yet"
            )
        case .openclaw:
            return (
                sourceMode ?? "openclaw_session_store_live",
                "missing_configuration",
                "OpenClaw is not detected or has no session activity yet"
            )
        }
    }

    private func offlineDashboardRecoveryPolicy(for provider: ProviderCode) -> String {
        switch provider {
        case .claude:
            return "known_transcript_only"
        case .codex:
            return "automatic_supported"
        case .gemini:
            return "unavailable"
        case .cursor:
            return "api_sync_supported"
        case .openclaw:
            return "automatic_supported"
        }
    }

    private func liveGameplayArmed(
        provider: ProviderCode,
        sourceMode: String?,
        healthState: String,
        hasLiveGameplayBoundary: Bool
    ) -> Bool {
        guard hasLiveGameplayBoundary else {
            return false
        }

        switch provider {
        case .codex:
            return healthState != "unsupported"
        case .claude:
            return healthState != "missing_configuration"
                && healthState != "unsupported"
                && sourceMode != "claude_transcript_backfill"
        case .gemini:
            return healthState != "missing_configuration" && healthState != "unsupported"
        case .cursor:
            return false
        case .openclaw:
            return healthState != "unsupported"
        }
    }

    private func reliabilityLabel(
        provider: ProviderCode,
        sourceMode: String?,
        healthState: String
    ) -> String {
        if healthState == "degraded" || healthState == "unsupported" {
            return "degraded"
        }

        switch provider {
        case .claude:
            return sourceMode == "claude_transcript_live" ? "best_effort" : "first_class"
        case .gemini:
            return "first_class"
        case .codex:
            return sourceMode == "codex_exec_json" ? "managed_first_class" : "best_effort"
        case .cursor:
            return "stats_only"
        case .openclaw:
            return "best_effort"
        }
    }

    private func providerDiagnosticFacts(
        provider: ProviderCode,
        database: SQLiteDatabase
    ) throws -> [String: String] {
        switch provider {
        case .cursor:
            let accountUsageSamples = try database.fetchOne(
                "SELECT COUNT(*) FROM account_usage_samples WHERE provider_code = 'cursor';"
            ) { statement in
                SQLiteDatabase.columnInt64(statement, index: 0)
            } ?? 0
            let legacyUsageSamples = try database.fetchOne(
                "SELECT COUNT(*) FROM usage_samples WHERE provider_code = 'cursor';"
            ) { statement in
                SQLiteDatabase.columnInt64(statement, index: 0)
            } ?? 0
            let legacyGameplayDeltaTokens = try database.fetchOne(
                "SELECT COALESCE(SUM(gameplay_delta_tokens), 0) FROM usage_samples WHERE provider_code = 'cursor';"
            ) { statement in
                SQLiteDatabase.columnInt64(statement, index: 0)
            } ?? 0
            let legacyCursorEncounters = try database.fetchOne(
                """
                SELECT COUNT(*)
                FROM encounters e
                INNER JOIN usage_samples us
                    ON us.usage_sample_id = e.usage_sample_id
                WHERE us.provider_code = 'cursor';
                """
            ) { statement in
                SQLiteDatabase.columnInt64(statement, index: 0)
            } ?? 0

            return [
                "account_usage_samples": "\(accountUsageSamples)",
                "legacy_usage_samples": "\(legacyUsageSamples)",
                "legacy_gameplay_delta_tokens": "\(legacyGameplayDeltaTokens)",
                "legacy_cursor_encounters": "\(legacyCursorEncounters)",
                "legacy_cursor_gameplay_history_detected": legacyCursorEncounters > 0 ? "yes" : "no",
            ]
        case .claude, .codex, .gemini, .openclaw:
            return [:]
        }
    }
}
