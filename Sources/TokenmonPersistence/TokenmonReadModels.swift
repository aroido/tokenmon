import Foundation
import TokenmonDomain

public struct CurrentRunSummary: Equatable, Sendable {
    public let providerSessions: Int
    public let usageSamples: Int
    public let totalNormalizedTokens: Int64
    public let tokensSinceLastEncounter: Int64
    public let nextEncounterThresholdTokens: Int64
    public let tokensUntilNextEncounter: Int64
    public let totalEncounters: Int64
    public let totalCaptures: Int64
    public let seenSpeciesCount: Int
    public let capturedSpeciesCount: Int
    public let latestUsageSampleObservedAt: String?
    public let latestEncounterOccurredAt: String?
}

public struct RecentEncounterSummary: Equatable, Sendable {
    public let encounterID: String
    public let encounterSequence: Int64
    public let occurredAt: String
    public let provider: ProviderCode?
    public let field: FieldType
    public let rarity: RarityTier
    public let speciesID: String
    public let speciesName: String
    public let assetKey: String
    public let seenCount: Int64
    public let capturedCount: Int64
    public let burstIntensityBand: Int
    public let captureProbability: Double
    public let captureRoll: Double
    public let outcome: EncounterOutcome
}

public struct DexSeenSummaryEntry: Equatable, Sendable {
    public let speciesID: String
    public let speciesName: String
    public let field: FieldType
    public let rarity: RarityTier
    public let sortOrder: Int
    public let firstSeenAt: String
    public let lastSeenAt: String
    public let seenCount: Int64
    public let capturedCount: Int64
    public let lastEncounterID: String
}

public struct DexCapturedSummaryEntry: Equatable, Sendable {
    public let speciesID: String
    public let speciesName: String
    public let field: FieldType
    public let rarity: RarityTier
    public let sortOrder: Int
    public let firstCapturedAt: String
    public let lastCapturedAt: String
    public let capturedCount: Int64
    public let lastEncounterID: String
}

public enum DexEntryStatus: String, CaseIterable, Sendable {
    case captured
    case seenUncaptured
    case unknown
}

public struct DexEntrySummary: Equatable, Sendable {
    public let speciesID: String
    public let speciesName: String
    public let field: FieldType
    public let rarity: RarityTier
    public let assetKey: String
    public let flavorText: String?
    public let sortOrder: Int
    public let status: DexEntryStatus
    public let seenCount: Int64
    public let capturedCount: Int64
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let firstCapturedAt: String?
    public let lastCapturedAt: String?
    public let stats: SpeciesStatBlock
}

public struct TodayActivitySummary: Equatable, Sendable {
    public let encounterCount: Int
    public let captureCount: Int
}

public struct DailyEncounterBucket: Equatable, Sendable {
    public let date: Date
    public let captures: Int
    public let escapes: Int
}

public struct TokenUsageTotals: Equatable, Sendable {
    public let todayTokens: Int64
    public let allTimeTokens: Int64

    public init(todayTokens: Int64, allTimeTokens: Int64) {
        self.todayTokens = todayTokens
        self.allTimeTokens = allTimeTokens
    }
}

public struct TokenUsageSourceSummary: Equatable, Sendable {
    public let hasAccountUsage: Bool
    public let hasLocalUsage: Bool
    public let accountBackedProvidersToday: [ProviderCode]
    public let localOnlyProvidersToday: [ProviderCode]

    public init(
        hasAccountUsage: Bool,
        hasLocalUsage: Bool,
        accountBackedProvidersToday: [ProviderCode],
        localOnlyProvidersToday: [ProviderCode]
    ) {
        self.hasAccountUsage = hasAccountUsage
        self.hasLocalUsage = hasLocalUsage
        self.accountBackedProvidersToday = accountBackedProvidersToday
        self.localOnlyProvidersToday = localOnlyProvidersToday
    }
}

public struct HourTokenBucket: Equatable, Sendable {
    public let date: Date
    public let tokens: Int64

    public init(date: Date, tokens: Int64) {
        self.date = date
        self.tokens = tokens
    }
}

public struct ProviderSessionTokens: Equatable, Sendable {
    public let providerSessionRowID: Int64
    public let provider: ProviderCode
    public let providerSessionID: String
    public let startedAt: String?
    public let lastSeenAt: String
    public let modelSlug: String?
    public let totalTokens: Int64

    public init(
        providerSessionRowID: Int64,
        provider: ProviderCode,
        providerSessionID: String,
        startedAt: String?,
        lastSeenAt: String,
        modelSlug: String?,
        totalTokens: Int64
    ) {
        self.providerSessionRowID = providerSessionRowID
        self.provider = provider
        self.providerSessionID = providerSessionID
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.modelSlug = modelSlug
        self.totalTokens = totalTokens
    }
}

public struct PartyMemberSummary: Equatable, Sendable {
    public let speciesID: String
    public let assetKey: String
    public let field: FieldType
    public let rarity: RarityTier
    public let displayName: String
    public let addedAt: String
    public let slotOrder: Int
    public let capturedCount: Int64
    public let stats: SpeciesStatBlock
}

public enum AmbientCompanionRoster: Equatable, Sendable {
    case byField([FieldType: [String]])
    case partyOverride([String])
}

public enum PartyStoreError: Error, LocalizedError, Equatable {
    case partyFull
    case partyNotCapturedYet(speciesID: String)

    public var errorDescription: String? {
        switch self {
        case .partyFull:
            return "Party is at maximum capacity."
        case .partyNotCapturedYet(let id):
            return "Species \(id) is not captured yet and cannot be added to the party."
        }
    }
}

public struct ProviderSessionSummary: Equatable, Sendable {
    public let providerSessionRowID: Int64
    public let provider: ProviderCode
    public let providerSessionID: String
    public let sourceMode: String
    public let modelSlug: String?
    public let workspaceDir: String?
    public let transcriptPath: String?
    public let startedAt: String?
    public let endedAt: String?
    public let lastSeenAt: String
    public let sessionState: String
}

public struct ProviderIngestEventSummary: Equatable, Sendable {
    public let providerIngestEventID: Int64
    public let provider: ProviderCode
    public let sourceMode: String
    public let providerSessionID: String?
    public let acceptanceState: String
    public let rejectionReason: String?
    public let providerEventFingerprint: String
    public let rawReferenceKind: String
    public let rawReferenceEventName: String?
    public let rawReferenceOffset: String?
    public let observedAt: String
    public let createdAt: String
    public let gameplayEligibility: String?
    public let gameplayDeltaTokens: Int64?
    public let gameplayBalanceBucket: String?
    public let gameplayBalanceWeight: Double?
    public let gameplayBalancePolicy: String?
}


public extension TokenmonDatabaseManager {
    private func readModelDatabase(_ providedDatabase: SQLiteDatabase?) throws -> SQLiteDatabase {
        if let providedDatabase {
            return providedDatabase
        }
        return try open()
    }

    func currentRunSummary(database providedDatabase: SQLiteDatabase? = nil) throws -> CurrentRunSummary {
        let database = try readModelDatabase(providedDatabase)

        guard let summary = try database.fetchOne(
            """
            SELECT exploration_state_id,
                   (SELECT COUNT(*) FROM provider_sessions) AS provider_sessions_count,
                   (SELECT COUNT(*)
                    FROM usage_samples
                    WHERE gameplay_eligibility = 'eligible_live') AS usage_samples_count,
                   total_normalized_tokens,
                   tokens_since_last_encounter,
                   next_encounter_threshold_tokens,
                   total_encounters,
                   total_captures,
                   (SELECT COUNT(*) FROM dex_seen) AS seen_species_count,
                   (SELECT COUNT(*) FROM dex_captured) AS captured_species_count,
                   (SELECT observed_at
                    FROM usage_samples
                    WHERE gameplay_eligibility = 'eligible_live'
                    ORDER BY usage_sample_id DESC
                    LIMIT 1) AS latest_usage_sample_observed_at,
                   (SELECT occurred_at
                    FROM encounters
                    ORDER BY encounter_sequence DESC
                    LIMIT 1) AS latest_encounter_occurred_at
            FROM exploration_state
            WHERE exploration_state_id = 1
            LIMIT 1;
            """,
            map: { statement in
                let tokensSinceLastEncounter = SQLiteDatabase.columnInt64(statement, index: 4)
                let nextEncounterThresholdTokens = SQLiteDatabase.columnInt64(statement, index: 5)
                let totalEncounters = SQLiteDatabase.columnInt64(statement, index: 6)
                let tokensUntilNextEncounter = max(0, nextEncounterThresholdTokens - tokensSinceLastEncounter)

                return CurrentRunSummary(
                    providerSessions: Int(SQLiteDatabase.columnInt64(statement, index: 1)),
                    usageSamples: Int(SQLiteDatabase.columnInt64(statement, index: 2)),
                    totalNormalizedTokens: SQLiteDatabase.columnInt64(statement, index: 3),
                    tokensSinceLastEncounter: tokensSinceLastEncounter,
                    nextEncounterThresholdTokens: nextEncounterThresholdTokens,
                    tokensUntilNextEncounter: tokensUntilNextEncounter,
                    totalEncounters: totalEncounters,
                    totalCaptures: SQLiteDatabase.columnInt64(statement, index: 7),
                    seenSpeciesCount: Int(SQLiteDatabase.columnInt64(statement, index: 8)),
                    capturedSpeciesCount: Int(SQLiteDatabase.columnInt64(statement, index: 9)),
                    latestUsageSampleObservedAt: SQLiteDatabase.columnOptionalText(statement, index: 10),
                    latestEncounterOccurredAt: SQLiteDatabase.columnOptionalText(statement, index: 11)
                )
            }
        ) else {
            throw SQLiteError.statementFailed(
                message: "missing exploration_state row",
                sql: "SELECT ... FROM exploration_state WHERE exploration_state_id = 1"
            )
        }

        return summary
    }

    func recentEncounterSummaries(limit: Int = 5, database providedDatabase: SQLiteDatabase? = nil) throws -> [RecentEncounterSummary] {
        guard limit > 0 else {
            return []
        }

        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT encounters.encounter_id,
               encounters.encounter_sequence,
               encounters.occurred_at,
               encounters.provider_code,
               encounters.field_code,
               encounters.rarity_tier,
               encounters.species_id,
               species.name,
               species.asset_key,
               COALESCE(dex_seen.seen_count, 0) AS seen_count,
               COALESCE(dex_captured.captured_count, 0) AS captured_count,
               encounters.burst_intensity_band,
               encounters.capture_probability,
               encounters.capture_roll,
               encounters.outcome
        FROM encounters
        INNER JOIN species ON species.species_id = encounters.species_id
        LEFT JOIN dex_seen ON dex_seen.species_id = encounters.species_id
        LEFT JOIN dex_captured ON dex_captured.species_id = encounters.species_id
        ORDER BY encounters.encounter_sequence DESC, encounters.encounter_id DESC
        LIMIT ?;
        """

        return try database.fetchAll(sql, bindings: [.integer(Int64(limit))]) { statement in
            let provider = SQLiteDatabase.columnOptionalText(statement, index: 3)
                .flatMap(ProviderCode.init(rawValue:))
            let field = try decodeFieldType(SQLiteDatabase.columnText(statement, index: 4), sql: sql)
            let rarity = try decodeRarityTier(SQLiteDatabase.columnText(statement, index: 5), sql: sql)
            let outcome = try decodeEncounterOutcome(SQLiteDatabase.columnText(statement, index: 14), sql: sql)

            return RecentEncounterSummary(
                encounterID: SQLiteDatabase.columnText(statement, index: 0),
                encounterSequence: SQLiteDatabase.columnInt64(statement, index: 1),
                occurredAt: SQLiteDatabase.columnText(statement, index: 2),
                provider: provider,
                field: field,
                rarity: rarity,
                speciesID: SQLiteDatabase.columnText(statement, index: 6),
                speciesName: SQLiteDatabase.columnText(statement, index: 7),
                assetKey: SQLiteDatabase.columnText(statement, index: 8),
                seenCount: SQLiteDatabase.columnInt64(statement, index: 9),
                capturedCount: SQLiteDatabase.columnInt64(statement, index: 10),
                burstIntensityBand: Int(SQLiteDatabase.columnInt64(statement, index: 11)),
                captureProbability: SQLiteDatabase.columnDouble(statement, index: 12),
                captureRoll: SQLiteDatabase.columnDouble(statement, index: 13),
                outcome: outcome
            )
        }
    }

    func dexSeenSummaries(database providedDatabase: SQLiteDatabase? = nil) throws -> [DexSeenSummaryEntry] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT dex_seen.species_id,
               species.name,
               species.field_code,
               species.rarity_tier,
               species.sort_order,
               dex_seen.first_seen_at,
               dex_seen.last_seen_at,
               dex_seen.seen_count,
               COALESCE(dex_captured.captured_count, 0) AS captured_count,
               dex_seen.last_encounter_id
        FROM dex_seen
        INNER JOIN species ON species.species_id = dex_seen.species_id
        LEFT JOIN dex_captured ON dex_captured.species_id = dex_seen.species_id
        ORDER BY species.sort_order ASC, dex_seen.species_id ASC;
        """

        return try database.fetchAll(sql) { statement in
            let field = try decodeFieldType(SQLiteDatabase.columnText(statement, index: 2), sql: sql)
            let rarity = try decodeRarityTier(SQLiteDatabase.columnText(statement, index: 3), sql: sql)

            return DexSeenSummaryEntry(
                speciesID: SQLiteDatabase.columnText(statement, index: 0),
                speciesName: SQLiteDatabase.columnText(statement, index: 1),
                field: field,
                rarity: rarity,
                sortOrder: Int(SQLiteDatabase.columnInt64(statement, index: 4)),
                firstSeenAt: SQLiteDatabase.columnText(statement, index: 5),
                lastSeenAt: SQLiteDatabase.columnText(statement, index: 6),
                seenCount: SQLiteDatabase.columnInt64(statement, index: 7),
                capturedCount: SQLiteDatabase.columnInt64(statement, index: 8),
                lastEncounterID: SQLiteDatabase.columnText(statement, index: 9)
            )
        }
    }

    func dexCapturedSummaries(database providedDatabase: SQLiteDatabase? = nil) throws -> [DexCapturedSummaryEntry] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT dex_captured.species_id,
               species.name,
               species.field_code,
               species.rarity_tier,
               species.sort_order,
               dex_captured.first_captured_at,
               dex_captured.last_captured_at,
               dex_captured.captured_count,
               dex_captured.last_encounter_id
        FROM dex_captured
        INNER JOIN species ON species.species_id = dex_captured.species_id
        ORDER BY species.sort_order ASC, dex_captured.species_id ASC;
        """

        return try database.fetchAll(sql) { statement in
            let field = try decodeFieldType(SQLiteDatabase.columnText(statement, index: 2), sql: sql)
            let rarity = try decodeRarityTier(SQLiteDatabase.columnText(statement, index: 3), sql: sql)

            return DexCapturedSummaryEntry(
                speciesID: SQLiteDatabase.columnText(statement, index: 0),
                speciesName: SQLiteDatabase.columnText(statement, index: 1),
                field: field,
                rarity: rarity,
                sortOrder: Int(SQLiteDatabase.columnInt64(statement, index: 4)),
                firstCapturedAt: SQLiteDatabase.columnText(statement, index: 5),
                lastCapturedAt: SQLiteDatabase.columnText(statement, index: 6),
                capturedCount: SQLiteDatabase.columnInt64(statement, index: 7),
                lastEncounterID: SQLiteDatabase.columnText(statement, index: 8)
            )
        }
    }

    func dexEntrySummaries(database providedDatabase: SQLiteDatabase? = nil) throws -> [DexEntrySummary] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT species.species_id,
               species.name,
               species.field_code,
               species.rarity_tier,
               species.asset_key,
               species.flavor_text,
               species.sort_order,
               dex_seen.first_seen_at,
               dex_seen.last_seen_at,
               COALESCE(dex_seen.seen_count, 0) AS seen_count,
               dex_captured.first_captured_at,
               dex_captured.last_captured_at,
               COALESCE(dex_captured.captured_count, 0) AS captured_count,
               species.stat_planning,
               species.stat_design,
               species.stat_frontend,
               species.stat_backend,
               species.stat_pm,
               species.stat_infra,
               species.traits_json
        FROM species
        LEFT JOIN dex_seen ON dex_seen.species_id = species.species_id
        LEFT JOIN dex_captured ON dex_captured.species_id = species.species_id
        WHERE species.is_active = 1
        ORDER BY species.sort_order ASC, species.species_id ASC;
        """

        return try database.fetchAll(sql) { statement in
            let field = try decodeFieldType(SQLiteDatabase.columnText(statement, index: 2), sql: sql)
            let rarity = try decodeRarityTier(SQLiteDatabase.columnText(statement, index: 3), sql: sql)
            let seenCount = SQLiteDatabase.columnInt64(statement, index: 9)
            let capturedCount = SQLiteDatabase.columnInt64(statement, index: 12)

            let status: DexEntryStatus
            if capturedCount > 0 {
                status = .captured
            } else if seenCount > 0 {
                status = .seenUncaptured
            } else {
                status = .unknown
            }

            let statPlanning = Int(SQLiteDatabase.columnInt64(statement, index: 13))
            let statDesign = Int(SQLiteDatabase.columnInt64(statement, index: 14))
            let statFrontend = Int(SQLiteDatabase.columnInt64(statement, index: 15))
            let statBackend = Int(SQLiteDatabase.columnInt64(statement, index: 16))
            let statPM = Int(SQLiteDatabase.columnInt64(statement, index: 17))
            let statInfra = Int(SQLiteDatabase.columnInt64(statement, index: 18))
            let traitsJSON = SQLiteDatabase.columnText(statement, index: 19)
            let traits = (try? JSONDecoder().decode([String].self, from: Data(traitsJSON.utf8))) ?? []

            let stats = SpeciesStatBlock(
                planning: statPlanning,
                design: statDesign,
                frontend: statFrontend,
                backend: statBackend,
                pm: statPM,
                infra: statInfra,
                traits: traits
            )

            return DexEntrySummary(
                speciesID: SQLiteDatabase.columnText(statement, index: 0),
                speciesName: SQLiteDatabase.columnText(statement, index: 1),
                field: field,
                rarity: rarity,
                assetKey: SQLiteDatabase.columnText(statement, index: 4),
                flavorText: SQLiteDatabase.columnOptionalText(statement, index: 5),
                sortOrder: Int(SQLiteDatabase.columnInt64(statement, index: 6)),
                status: status,
                seenCount: seenCount,
                capturedCount: capturedCount,
                firstSeenAt: SQLiteDatabase.columnOptionalText(statement, index: 7),
                lastSeenAt: SQLiteDatabase.columnOptionalText(statement, index: 8),
                firstCapturedAt: SQLiteDatabase.columnOptionalText(statement, index: 10),
                lastCapturedAt: SQLiteDatabase.columnOptionalText(statement, index: 11),
                stats: stats
            )
        }
    }

    func encounterFieldDistribution(database providedDatabase: SQLiteDatabase? = nil) throws -> [FieldType: Int] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT field_code, COUNT(*)
        FROM encounters
        GROUP BY field_code;
        """

        let rows: [(String, Int64)] = try database.fetchAll(sql) { statement in
            (
                SQLiteDatabase.columnText(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1)
            )
        }

        var result: [FieldType: Int] = [:]
        for (fieldCode, count) in rows {
            guard let field = FieldType(rawValue: fieldCode) else {
                continue
            }
            result[field] = Int(count)
        }
        return result
    }

    func todayActivitySummary(database providedDatabase: SQLiteDatabase? = nil) throws -> TodayActivitySummary {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT outcome, COUNT(*)
        FROM encounters
        WHERE date(occurred_at, 'localtime') = date('now', 'localtime')
        GROUP BY outcome;
        """

        var encounterCount = 0
        var captureCount = 0
        let rows: [(String, Int64)] = try database.fetchAll(sql) { statement in
            (
                SQLiteDatabase.columnText(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1)
            )
        }
        for (outcome, count) in rows {
            encounterCount += Int(count)
            if outcome == EncounterOutcome.captured.rawValue {
                captureCount += Int(count)
            }
        }
        return TodayActivitySummary(encounterCount: encounterCount, captureCount: captureCount)
    }

    func tokenUsageTotals(database providedDatabase: SQLiteDatabase? = nil) throws -> TokenUsageTotals {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        WITH account_days AS (
            SELECT provider_code,
                   date(observed_at, 'localtime') AS day,
                   SUM(normalized_delta_tokens) AS tokens
            FROM account_usage_samples
            GROUP BY provider_code, day
        ),
        local_days AS (
            SELECT provider_code,
                   date(observed_at, 'localtime') AS day,
                   SUM(normalized_delta_tokens) AS tokens
            FROM usage_samples
            WHERE NOT EXISTS (
                SELECT 1
                FROM account_days
                WHERE account_days.provider_code = usage_samples.provider_code
                  AND account_days.day = date(usage_samples.observed_at, 'localtime')
            )
            GROUP BY provider_code, day
        ),
        combined_days AS (
            SELECT provider_code, day, tokens FROM account_days
            UNION ALL
            SELECT provider_code, day, tokens FROM local_days
        )
        SELECT
            COALESCE(SUM(CASE WHEN day = date('now', 'localtime') THEN tokens ELSE 0 END), 0) AS today_tokens,
            COALESCE(SUM(tokens), 0) AS all_time_tokens
        FROM combined_days;
        """

        guard let totals = try database.fetchOne(sql, map: { statement in
            TokenUsageTotals(
                todayTokens: SQLiteDatabase.columnInt64(statement, index: 0),
                allTimeTokens: SQLiteDatabase.columnInt64(statement, index: 1)
            )
        }) else {
            return TokenUsageTotals(todayTokens: 0, allTimeTokens: 0)
        }
        return totals
    }

    func tokenByProviderToday(database providedDatabase: SQLiteDatabase? = nil) throws -> [ProviderCode: Int64] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        WITH account_today AS (
            SELECT provider_code, SUM(normalized_delta_tokens) AS tokens
            FROM account_usage_samples
            WHERE date(observed_at, 'localtime') = date('now', 'localtime')
            GROUP BY provider_code
        ),
        local_today AS (
            SELECT provider_code, SUM(normalized_delta_tokens) AS tokens
            FROM usage_samples
            WHERE date(observed_at, 'localtime') = date('now', 'localtime')
              AND provider_code NOT IN (SELECT provider_code FROM account_today)
            GROUP BY provider_code
        )
        SELECT provider_code, tokens FROM account_today
        UNION ALL
        SELECT provider_code, tokens FROM local_today;
        """

        let rows: [(String, Int64)] = try database.fetchAll(sql) { statement in
            (
                SQLiteDatabase.columnText(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1)
            )
        }

        var result: [ProviderCode: Int64] = [:]
        for (code, sum) in rows {
            guard let provider = ProviderCode(rawValue: code) else {
                continue
            }
            result[provider] = sum
        }
        return result
    }

    func tokenHourlyRolling24(database providedDatabase: SQLiteDatabase? = nil) throws -> [HourTokenBucket] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        WITH account_days AS (
            SELECT DISTINCT provider_code,
                   date(observed_at, 'localtime') AS day
            FROM account_usage_samples
        ),
        account_hours AS (
            SELECT strftime('%Y-%m-%d %H', observed_at, 'localtime') AS hour,
                   SUM(normalized_delta_tokens) AS tokens
            FROM account_usage_samples
            WHERE observed_at >= datetime('now', '-24 hours')
            GROUP BY hour
        ),
        local_hours AS (
            SELECT strftime('%Y-%m-%d %H', observed_at, 'localtime') AS hour,
                   SUM(normalized_delta_tokens) AS tokens
            FROM usage_samples
            WHERE observed_at >= datetime('now', '-24 hours')
              AND NOT EXISTS (
                  SELECT 1
                  FROM account_days
                  WHERE account_days.provider_code = usage_samples.provider_code
                    AND account_days.day = date(usage_samples.observed_at, 'localtime')
              )
            GROUP BY hour
        ),
        combined_hours AS (
            SELECT hour, tokens FROM account_hours
            UNION ALL
            SELECT hour, tokens FROM local_hours
        )
        SELECT hour, SUM(tokens)
        FROM combined_hours
        GROUP BY hour;
        """

        let rows: [(String, Int64)] = try database.fetchAll(sql) { statement in
            (
                SQLiteDatabase.columnText(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1)
            )
        }

        var tokensByHourKey: [String: Int64] = [:]
        for (hourKey, sum) in rows {
            tokensByHourKey[hourKey] = sum
        }

        // Build 24 hour buckets aligned to local-time hour boundaries:
        // [now-23h .. now], oldest first.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH"
        formatter.calendar = calendar
        formatter.timeZone = .current

        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        guard let currentHour = calendar.date(from: components) else {
            return []
        }

        var buckets: [HourTokenBucket] = []
        for offset in stride(from: 23, through: 0, by: -1) {
            guard let hour = calendar.date(byAdding: .hour, value: -offset, to: currentHour) else {
                continue
            }
            let key = formatter.string(from: hour)
            buckets.append(
                HourTokenBucket(
                    date: hour,
                    tokens: tokensByHourKey[key] ?? 0
                )
            )
        }
        return buckets
    }

    func tokenUsageSourceSummary(database providedDatabase: SQLiteDatabase? = nil) throws -> TokenUsageSourceSummary {
        let database = try readModelDatabase(providedDatabase)
        let hasAccountUsage = try database.fetchOne(
            "SELECT 1 FROM account_usage_samples LIMIT 1;"
        ) { _ in true } ?? false
        let hasLocalUsage = try database.fetchOne(
            "SELECT 1 FROM usage_samples LIMIT 1;"
        ) { _ in true } ?? false

        let accountProviders = try providersForSQL(
            """
            SELECT DISTINCT provider_code
            FROM account_usage_samples
            WHERE date(observed_at, 'localtime') = date('now', 'localtime')
            ORDER BY provider_code;
            """,
            database: database
        )
        let localOnlyProviders = try providersForSQL(
            """
            SELECT DISTINCT provider_code
            FROM usage_samples
            WHERE date(observed_at, 'localtime') = date('now', 'localtime')
              AND provider_code NOT IN (
                  SELECT DISTINCT provider_code
                  FROM account_usage_samples
                  WHERE date(observed_at, 'localtime') = date('now', 'localtime')
              )
            ORDER BY provider_code;
            """,
            database: database
        )

        return TokenUsageSourceSummary(
            hasAccountUsage: hasAccountUsage,
            hasLocalUsage: hasLocalUsage,
            accountBackedProvidersToday: accountProviders,
            localOnlyProvidersToday: localOnlyProviders
        )
    }

    func recentProviderSessions(limit: Int = 10, database providedDatabase: SQLiteDatabase? = nil) throws -> [ProviderSessionTokens] {
        guard limit > 0 else {
            return []
        }
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT ps.provider_session_row_id,
               ps.provider_code,
               ps.provider_session_id,
               ps.started_at,
               ps.last_seen_at,
               ps.model_slug,
               COALESCE(SUM(us.normalized_delta_tokens), 0) AS total_tokens
        FROM provider_sessions ps
        LEFT JOIN usage_samples us
            ON us.provider_session_row_id = ps.provider_session_row_id
        GROUP BY ps.provider_session_row_id
        HAVING COALESCE(SUM(us.normalized_delta_tokens), 0) > 0
        ORDER BY ps.last_seen_at DESC
        LIMIT ?;
        """

        return try database.fetchAll(sql, bindings: [.integer(Int64(limit))]) { statement in
            let providerCode = SQLiteDatabase.columnText(statement, index: 1)
            let provider = ProviderCode(rawValue: providerCode) ?? .claude
            return ProviderSessionTokens(
                providerSessionRowID: SQLiteDatabase.columnInt64(statement, index: 0),
                provider: provider,
                providerSessionID: SQLiteDatabase.columnText(statement, index: 2),
                startedAt: SQLiteDatabase.columnOptionalText(statement, index: 3),
                lastSeenAt: SQLiteDatabase.columnText(statement, index: 4),
                modelSlug: SQLiteDatabase.columnOptionalText(statement, index: 5),
                totalTokens: SQLiteDatabase.columnInt64(statement, index: 6)
            )
        }
    }

    private func providersForSQL(_ sql: String, database: SQLiteDatabase) throws -> [ProviderCode] {
        let rows = try database.fetchAll(sql) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        return rows.compactMap(ProviderCode.init(rawValue:))
    }

    func ambientCompanionRoster(limit: Int = 24, database providedDatabase: SQLiteDatabase? = nil) throws -> AmbientCompanionRoster {
        let database = try readModelDatabase(providedDatabase)

        let partyCount = try database.fetchOne("SELECT COUNT(*) FROM party_members;") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0

        if partyCount > 0 {
            let partySQL = """
            SELECT species.asset_key
            FROM party_members
            INNER JOIN species ON species.species_id = party_members.species_id
            WHERE species.is_active = 1
            ORDER BY party_members.slot_order ASC;
            """
            let assetKeys: [String] = try database.fetchAll(partySQL) { statement in
                SQLiteDatabase.columnText(statement, index: 0)
            }
            return .partyOverride(assetKeys.filter { $0.isEmpty == false })
        }

        guard limit > 0 else {
            return .byField([:])
        }

        let sql = """
        SELECT species.field_code,
               species.asset_key,
               dex_captured.last_captured_at
        FROM dex_captured
        INNER JOIN species ON species.species_id = dex_captured.species_id
        WHERE species.is_active = 1
        ORDER BY dex_captured.last_captured_at DESC, species.sort_order ASC
        LIMIT ?;
        """

        var summariesByField: [FieldType: [String]] = [:]
        let rows: [(FieldType, String)] = try database.fetchAll(sql, bindings: [.integer(Int64(limit))]) { statement in
            let field = try decodeFieldType(SQLiteDatabase.columnText(statement, index: 0), sql: sql)
            let assetKey = SQLiteDatabase.columnText(statement, index: 1)
            return (field, assetKey)
        }

        for (field, assetKey) in rows {
            guard assetKey.isEmpty == false else { continue }
            var existing = summariesByField[field, default: []]
            guard existing.contains(assetKey) == false else { continue }
            existing.append(assetKey)
            summariesByField[field] = existing
        }

        return .byField(summariesByField)
    }

    func recentProviderSessionSummaries(limit: Int = 20, database providedDatabase: SQLiteDatabase? = nil) throws -> [ProviderSessionSummary] {
        guard limit > 0 else {
            return []
        }

        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT provider_session_row_id,
               provider_code,
               provider_session_id,
               source_mode,
               model_slug,
               workspace_dir,
               transcript_path,
               started_at,
               ended_at,
               last_seen_at,
               session_state
        FROM provider_sessions
        ORDER BY last_seen_at DESC, provider_session_row_id DESC
        LIMIT ?;
        """

        return try database.fetchAll(sql, bindings: [.integer(Int64(limit))]) { statement in
            let provider = try decodeProviderCode(SQLiteDatabase.columnText(statement, index: 1), sql: sql)

            return ProviderSessionSummary(
                providerSessionRowID: SQLiteDatabase.columnInt64(statement, index: 0),
                provider: provider,
                providerSessionID: SQLiteDatabase.columnText(statement, index: 2),
                sourceMode: SQLiteDatabase.columnText(statement, index: 3),
                modelSlug: SQLiteDatabase.columnOptionalText(statement, index: 4),
                workspaceDir: SQLiteDatabase.columnOptionalText(statement, index: 5),
                transcriptPath: SQLiteDatabase.columnOptionalText(statement, index: 6),
                startedAt: SQLiteDatabase.columnOptionalText(statement, index: 7),
                endedAt: SQLiteDatabase.columnOptionalText(statement, index: 8),
                lastSeenAt: SQLiteDatabase.columnText(statement, index: 9),
                sessionState: SQLiteDatabase.columnText(statement, index: 10)
            )
        }
    }

    func recentProviderIngestEventSummaries(limit: Int = 40, database providedDatabase: SQLiteDatabase? = nil) throws -> [ProviderIngestEventSummary] {
        guard limit > 0 else {
            return []
        }

        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT provider_ingest_events.provider_ingest_event_id,
               provider_ingest_events.provider_code,
               provider_ingest_events.source_mode,
               provider_sessions.provider_session_id,
               provider_ingest_events.acceptance_state,
               provider_ingest_events.rejection_reason,
               provider_ingest_events.provider_event_fingerprint,
               provider_ingest_events.raw_reference_kind,
               provider_ingest_events.raw_reference_event_name,
               provider_ingest_events.raw_reference_offset,
               provider_ingest_events.observed_at,
               provider_ingest_events.created_at,
               usage_samples.gameplay_eligibility,
               usage_samples.gameplay_delta_tokens,
               usage_samples.gameplay_balance_bucket,
               usage_samples.gameplay_balance_weight,
               usage_samples.gameplay_balance_policy
        FROM provider_ingest_events
        LEFT JOIN provider_sessions
          ON provider_sessions.provider_session_row_id = provider_ingest_events.provider_session_row_id
        LEFT JOIN usage_samples
          ON usage_samples.provider_ingest_event_id = provider_ingest_events.provider_ingest_event_id
        ORDER BY provider_ingest_events.provider_ingest_event_id DESC
        LIMIT ?;
        """

        return try database.fetchAll(sql, bindings: [.integer(Int64(limit))]) { statement in
            let provider = try decodeProviderCode(SQLiteDatabase.columnText(statement, index: 1), sql: sql)

            return ProviderIngestEventSummary(
                providerIngestEventID: SQLiteDatabase.columnInt64(statement, index: 0),
                provider: provider,
                sourceMode: SQLiteDatabase.columnText(statement, index: 2),
                providerSessionID: SQLiteDatabase.columnOptionalText(statement, index: 3),
                acceptanceState: SQLiteDatabase.columnText(statement, index: 4),
                rejectionReason: SQLiteDatabase.columnOptionalText(statement, index: 5),
                providerEventFingerprint: SQLiteDatabase.columnText(statement, index: 6),
                rawReferenceKind: SQLiteDatabase.columnText(statement, index: 7),
                rawReferenceEventName: SQLiteDatabase.columnOptionalText(statement, index: 8),
                rawReferenceOffset: SQLiteDatabase.columnOptionalText(statement, index: 9),
                observedAt: SQLiteDatabase.columnText(statement, index: 10),
                createdAt: SQLiteDatabase.columnText(statement, index: 11),
                gameplayEligibility: SQLiteDatabase.columnOptionalText(statement, index: 12),
                gameplayDeltaTokens: SQLiteDatabase.columnOptionalInt64(statement, index: 13),
                gameplayBalanceBucket: SQLiteDatabase.columnOptionalText(statement, index: 14),
                gameplayBalanceWeight: SQLiteDatabase.columnOptionalDouble(statement, index: 15),
                gameplayBalancePolicy: SQLiteDatabase.columnOptionalText(statement, index: 16)
            )
        }
    }

    func encounterDailyTrend(days: Int = 7, database providedDatabase: SQLiteDatabase? = nil) throws -> [DailyEncounterBucket] {
        precondition(days > 0, "days must be positive")

        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT date(occurred_at, 'localtime') AS day, outcome, COUNT(*)
        FROM encounters
        WHERE date(occurred_at, 'localtime') >= date('now', ?, 'localtime')
        GROUP BY day, outcome;
        """

        let modifier = "-\(days - 1) days"
        let rows: [(String, String, Int64)] = try database.fetchAll(
            sql,
            bindings: [.text(modifier)]
        ) { statement in
            (
                SQLiteDatabase.columnText(statement, index: 0),
                SQLiteDatabase.columnText(statement, index: 1),
                SQLiteDatabase.columnInt64(statement, index: 2)
            )
        }

        // Index counts by yyyy-MM-dd day key.
        var captureByDay: [String: Int] = [:]
        var escapeByDay: [String: Int] = [:]
        for (day, outcome, count) in rows {
            if outcome == EncounterOutcome.captured.rawValue {
                captureByDay[day, default: 0] += Int(count)
            } else {
                escapeByDay[day, default: 0] += Int(count)
            }
        }

        // Build N buckets oldest -> newest, zero-filling missing days.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = calendar
        formatter.timeZone = .current

        let today = calendar.startOfDay(for: Date())
        var buckets: [DailyEncounterBucket] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let key = formatter.string(from: day)
            buckets.append(
                DailyEncounterBucket(
                    date: day,
                    captures: captureByDay[key] ?? 0,
                    escapes: escapeByDay[key] ?? 0
                )
            )
        }
        return buckets
    }

    func latestGeminiSessionTotals(
        activeWithinHours: Int = 24,
        asOf reference: Date = Date()
    ) throws -> [String: GeminiSessionRunningTotals] {
        try latestProviderSessionTotals(
            provider: .gemini,
            sourceModes: nil,
            activeWithinHours: activeWithinHours,
            asOf: reference
        )
    }

    func latestClaudeSessionTotals(
        activeWithinHours: Int = 24,
        asOf reference: Date = Date()
    ) throws -> [String: GeminiSessionRunningTotals] {
        try latestProviderSessionTotals(
            provider: .claude,
            sourceModes: ["claude_otel_api_request_live", "claude_statusline_live"],
            activeWithinHours: activeWithinHours,
            asOf: reference
        )
    }

    private func latestProviderSessionTotals(
        provider: ProviderCode,
        sourceModes: [String]?,
        activeWithinHours: Int,
        asOf reference: Date
    ) throws -> [String: GeminiSessionRunningTotals] {
        precondition(activeWithinHours > 0)

        let database = try open()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let cutoff = reference.addingTimeInterval(-Double(activeWithinHours) * 3600)
        let cutoffString = formatter.string(from: cutoff)

        var sql = """
        SELECT ps.provider_session_id,
               MAX(us.total_input_tokens),
               MAX(us.total_output_tokens),
               MAX(us.total_cached_input_tokens),
               MAX(us.normalized_total_tokens)
        FROM provider_sessions ps
        JOIN usage_samples us
          ON us.provider_session_row_id = ps.provider_session_row_id
         AND us.provider_code = ?
        JOIN provider_ingest_events pie
          ON pie.provider_ingest_event_id = us.provider_ingest_event_id
        WHERE ps.provider_code = ?
          AND us.observed_at >= ?
        """
        var bindings: [SQLiteValue] = [
            .text(provider.rawValue),
            .text(provider.rawValue),
            .text(cutoffString),
        ]
        if let sourceModes, sourceModes.isEmpty == false {
            let placeholders = Array(repeating: "?", count: sourceModes.count).joined(separator: ", ")
            sql += "\n  AND pie.source_mode IN (\(placeholders))"
            bindings.append(contentsOf: sourceModes.map { .text($0) })
        }
        sql += """

        GROUP BY ps.provider_session_id;
        """

        let rows: [(String, Int64, Int64, Int64, Int64)] = try database.fetchAll(
            sql,
            bindings: bindings
        ) { statement in
            (
                SQLiteDatabase.columnText(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1),
                SQLiteDatabase.columnInt64(statement, index: 2),
                SQLiteDatabase.columnInt64(statement, index: 3),
                SQLiteDatabase.columnInt64(statement, index: 4)
            )
        }

        var result: [String: GeminiSessionRunningTotals] = [:]
        for (sessionID, input, output, cached, total) in rows {
            result[sessionID] = GeminiSessionRunningTotals(
                totalInputTokens: input,
                totalOutputTokens: output,
                totalCachedInputTokens: cached,
                normalizedTotalTokens: total
            )
        }
        return result
    }

    func addToParty(speciesID: String) throws {
        let database = try open()

        let isCaptured = try database.fetchOne(
            "SELECT 1 FROM dex_captured WHERE species_id = ? LIMIT 1;",
            bindings: [.text(speciesID)]
        ) { _ in true } ?? false
        guard isCaptured else {
            throw PartyStoreError.partyNotCapturedYet(speciesID: speciesID)
        }

        let nowISO = ISO8601DateFormatter().string(from: Date())
        try database.inTransaction {
            let alreadyMember = try database.fetchOne(
                "SELECT 1 FROM party_members WHERE species_id = ? LIMIT 1;",
                bindings: [.text(speciesID)]
            ) { _ in true } ?? false
            guard alreadyMember == false else { return }

            let count = try database.fetchOne("SELECT COUNT(*) FROM party_members;") { statement in
                SQLiteDatabase.columnInt64(statement, index: 0)
            } ?? 0
            guard count < 10 else {
                throw PartyStoreError.partyFull
            }

            let nextSlot = (try database.fetchOne(
                "SELECT COALESCE(MAX(slot_order), 0) + 1 FROM party_members;"
            ) { SQLiteDatabase.columnInt64($0, index: 0) }) ?? 1

            try database.execute(
                "INSERT INTO party_members (species_id, slot_order, added_at) VALUES (?, ?, ?);",
                bindings: [.text(speciesID), .integer(nextSlot), .text(nowISO)]
            )
        }
    }

    func partyMemberSummaries(database providedDatabase: SQLiteDatabase? = nil) throws -> [PartyMemberSummary] {
        let database = try readModelDatabase(providedDatabase)
        let sql = """
        SELECT party_members.species_id,
               species.asset_key,
               species.field_code,
               species.rarity_tier,
               species.name,
               party_members.added_at,
               party_members.slot_order,
               dex_captured.captured_count,
               species.stat_planning,
               species.stat_design,
               species.stat_frontend,
               species.stat_backend,
               species.stat_pm,
               species.stat_infra,
               species.traits_json
        FROM party_members
        INNER JOIN species ON species.species_id = party_members.species_id
        INNER JOIN dex_captured ON dex_captured.species_id = party_members.species_id
        ORDER BY party_members.slot_order ASC;
        """
        return try database.fetchAll(sql) { statement in
            let speciesID = SQLiteDatabase.columnText(statement, index: 0)
            let assetKey = SQLiteDatabase.columnText(statement, index: 1)
            let field = try decodeFieldType(SQLiteDatabase.columnText(statement, index: 2), sql: sql)
            let rarity = try decodeRarityTier(SQLiteDatabase.columnText(statement, index: 3), sql: sql)
            let name = SQLiteDatabase.columnText(statement, index: 4)
            let addedAt = SQLiteDatabase.columnText(statement, index: 5)
            let slot = Int(SQLiteDatabase.columnInt64(statement, index: 6))
            let capturedCount = SQLiteDatabase.columnInt64(statement, index: 7)
            let traitsJSON = SQLiteDatabase.columnText(statement, index: 14)
            let traits = (try? JSONDecoder().decode([String].self, from: Data(traitsJSON.utf8))) ?? []
            let stats = SpeciesStatBlock(
                planning: Int(SQLiteDatabase.columnInt64(statement, index: 8)),
                design: Int(SQLiteDatabase.columnInt64(statement, index: 9)),
                frontend: Int(SQLiteDatabase.columnInt64(statement, index: 10)),
                backend: Int(SQLiteDatabase.columnInt64(statement, index: 11)),
                pm: Int(SQLiteDatabase.columnInt64(statement, index: 12)),
                infra: Int(SQLiteDatabase.columnInt64(statement, index: 13)),
                traits: traits
            )
            return PartyMemberSummary(
                speciesID: speciesID,
                assetKey: assetKey,
                field: field,
                rarity: rarity,
                displayName: name,
                addedAt: addedAt,
                slotOrder: slot,
                capturedCount: capturedCount,
                stats: stats
            )
        }
    }

    func removeFromParty(speciesID: String) throws {
        let database = try open()
        try database.execute(
            "DELETE FROM party_members WHERE species_id = ?;",
            bindings: [.text(speciesID)]
        )
    }

    func partySpeciesIDSet() throws -> Set<String> {
        let database = try open()
        let ids: [String] = try database.fetchAll(
            "SELECT species_id FROM party_members;"
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        return Set(ids)
    }

    func isPartyFull() throws -> Bool {
        let database = try open()
        let count = try database.fetchOne("SELECT COUNT(*) FROM party_members;") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        return count >= 10
    }
}

private func decodeFieldType(_ rawValue: String, sql: String) throws -> FieldType {
    guard let field = FieldType(rawValue: rawValue) else {
        throw SQLiteError.statementFailed(message: "invalid field_code \(rawValue)", sql: sql)
    }
    return field
}

private func decodeRarityTier(_ rawValue: String, sql: String) throws -> RarityTier {
    guard let rarity = RarityTier(rawValue: rawValue) else {
        throw SQLiteError.statementFailed(message: "invalid rarity_tier \(rawValue)", sql: sql)
    }
    return rarity
}

private func decodeProviderCode(_ rawValue: String, sql: String) throws -> ProviderCode {
    guard let provider = ProviderCode(rawValue: rawValue) else {
        throw SQLiteError.statementFailed(message: "invalid provider_code \(rawValue)", sql: sql)
    }
    return provider
}

private func decodeEncounterOutcome(_ rawValue: String, sql: String) throws -> EncounterOutcome {
    guard let outcome = EncounterOutcome(rawValue: rawValue) else {
        throw SQLiteError.statementFailed(message: "invalid encounter outcome \(rawValue)", sql: sql)
    }
    return outcome
}
