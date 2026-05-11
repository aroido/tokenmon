import Foundation
import TokenmonDomain
import TokenmonProviders

struct GameplayTokenBalanceDecision: Equatable, Sendable {
    let gameplayDeltaTokens: Int64
    let bucketKey: String?
    let appliedWeight: Double?
    let policy: String?
    let observedRateTokensPerMinute: Double?
}

private struct GameplayTokenBalanceBucketState {
    let bucketKey: String
    let providerCode: ProviderCode
    let modelBucket: String
    let effectiveWeight: Double
    let observedRateTokensPerMinute: Double
    let sampleCount: Int64
    let activeMinutes: Double
    let lastSampleAt: String?
}

enum GameplayTokenBalancer {
    private static let targetRateTokensPerMinute = 1_200.0
    private static let correctionAlpha = 0.85
    private static let smoothingPreviousWeight = 0.85
    private static let smoothingNewWeight = 0.15
    private static let minimumCorrectionWeight = 0.01
    private static let maximumCorrectionWeight = 2.50
    private static let coldStartMinimumSamples: Int64 = 3
    private static let coldStartMinimumActiveMinutes = 0.25
    private static let minimumIntervalMinutes = 5.0 / 60.0
    private static let maximumIntervalMinutes = 10.0
    private static let softCapThresholdTokens = 60_000.0
    private static let softCapOverflowMultiplier = 0.10
    private static let policyVersion = "gameplay_balance_v2"
    private static let seedSettingKey = "gameplay_balance_seed"
    private static let policySettingKey = "gameplay_balance_policy_version"

    static func balance(
        database: SQLiteDatabase,
        event: ProviderUsageSampleEvent,
        rawEligibleDeltaTokens: Int64
    ) throws -> GameplayTokenBalanceDecision {
        guard rawEligibleDeltaTokens > 0 else {
            return GameplayTokenBalanceDecision(
                gameplayDeltaTokens: 0,
                bucketKey: nil,
                appliedWeight: nil,
                policy: nil,
                observedRateTokensPerMinute: nil
            )
        }

        let bucketKey = bucketKey(provider: event.provider, modelSlug: event.modelSlug)
        let modelBucket = modelBucket(from: event.modelSlug)
        try ensurePolicyVersion(database: database)
        let bucketState = try loadBucketState(database: database, bucketKey: bucketKey)
        let fallbackWeight = providerFallbackWeight(event.provider)
        let previousWeight = bucketState?.effectiveWeight ?? fallbackWeight
        let previousRate = bucketState?.observedRateTokensPerMinute ?? 0
        let previousSampleCount = bucketState?.sampleCount ?? 0
        let previousActiveMinutes = bucketState?.activeMinutes ?? 0
        let observedIntervalMinutes = activeIntervalMinutes(
            previousObservedAt: bucketState?.lastSampleAt,
            currentObservedAt: event.observedAt
        )

        let enoughHistory = previousSampleCount >= coldStartMinimumSamples
            && previousActiveMinutes >= coldStartMinimumActiveMinutes
            && previousRate > 0
        let correctionWeight: Double
        let policyMode: String
        if enoughHistory {
            let rawCorrection = pow(targetRateTokensPerMinute / previousRate, correctionAlpha)
            let clampedCorrection = clamp(
                rawCorrection,
                minimumCorrectionWeight,
                maximumCorrectionWeight
            )
            correctionWeight = (previousWeight * smoothingPreviousWeight)
                + (clampedCorrection * smoothingNewWeight)
            policyMode = "dynamic_alpha_0_85"
        } else {
            correctionWeight = fallbackWeight
            policyMode = "cold_start_provider_fallback"
        }

        let savePacingMultiplier = try savePacingMultiplier(database: database)
        let appliedWeight = correctionWeight * savePacingMultiplier
        let weightedDelta = Double(rawEligibleDeltaTokens) * appliedWeight
        let (gameplayDelta, softCapApplied) = softCappedDelta(weightedDelta)
        let updatedRate = updatedObservedRate(
            previousRate: previousRate,
            intervalMinutes: observedIntervalMinutes,
            rawDeltaTokens: rawEligibleDeltaTokens
        )
        let updatedActiveMinutes = previousActiveMinutes + (observedIntervalMinutes ?? 0)
        let updatedSampleCount = previousSampleCount + 1
        let policy = [
            policyVersion,
            policyMode,
            softCapApplied ? "soft_cap" : "linear",
        ].joined(separator: ":")

        try upsertBucketState(
            database: database,
            bucketKey: bucketKey,
            provider: event.provider,
            modelBucket: modelBucket,
            effectiveWeight: correctionWeight,
            observedRateTokensPerMinute: updatedRate,
            sampleCount: updatedSampleCount,
            activeMinutes: updatedActiveMinutes,
            lastSampleAt: event.observedAt
        )

        return GameplayTokenBalanceDecision(
            gameplayDeltaTokens: gameplayDelta,
            bucketKey: bucketKey,
            appliedWeight: appliedWeight,
            policy: policy,
            observedRateTokensPerMinute: updatedRate > 0 ? updatedRate : nil
        )
    }

    private static func loadBucketState(
        database: SQLiteDatabase,
        bucketKey: String
    ) throws -> GameplayTokenBalanceBucketState? {
        try database.fetchOne(
            """
            SELECT bucket_key,
                   provider_code,
                   model_bucket,
                   effective_weight,
                   observed_rate_tokens_per_minute,
                   sample_count,
                   active_minutes,
                   last_sample_at
            FROM gameplay_balance_buckets
            WHERE bucket_key = ?
            LIMIT 1;
            """,
            bindings: [.text(bucketKey)]
        ) { statement in
            let rawProvider = SQLiteDatabase.columnText(statement, index: 1)
            let provider = ProviderCode(rawValue: rawProvider) ?? .codex
            return GameplayTokenBalanceBucketState(
                bucketKey: SQLiteDatabase.columnText(statement, index: 0),
                providerCode: provider,
                modelBucket: SQLiteDatabase.columnText(statement, index: 2),
                effectiveWeight: SQLiteDatabase.columnDouble(statement, index: 3),
                observedRateTokensPerMinute: SQLiteDatabase.columnDouble(statement, index: 4),
                sampleCount: SQLiteDatabase.columnInt64(statement, index: 5),
                activeMinutes: SQLiteDatabase.columnDouble(statement, index: 6),
                lastSampleAt: SQLiteDatabase.columnOptionalText(statement, index: 7)
            )
        }
    }

    private static func ensurePolicyVersion(database: SQLiteDatabase) throws {
        let currentPolicy = try database.fetchOne(
            """
            SELECT setting_value_json
            FROM settings
            WHERE setting_key = ?
            LIMIT 1;
            """,
            bindings: [.text(policySettingKey)]
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        let decoder = JSONDecoder()
        let decodedPolicy = currentPolicy.flatMap {
            try? decoder.decode(String.self, from: Data($0.utf8))
        }
        guard decodedPolicy != policyVersion else {
            return
        }

        try database.execute("DELETE FROM gameplay_balance_buckets;")
        let now = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO settings (
                setting_key,
                setting_value_json,
                updated_at
            ) VALUES (?, ?, ?)
            ON CONFLICT(setting_key) DO UPDATE SET
                setting_value_json = excluded.setting_value_json,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(policySettingKey),
                .text("\"\(policyVersion)\""),
                .text(now),
            ]
        )
    }

    private static func upsertBucketState(
        database: SQLiteDatabase,
        bucketKey: String,
        provider: ProviderCode,
        modelBucket: String,
        effectiveWeight: Double,
        observedRateTokensPerMinute: Double,
        sampleCount: Int64,
        activeMinutes: Double,
        lastSampleAt: String
    ) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO gameplay_balance_buckets (
                bucket_key,
                provider_code,
                model_bucket,
                effective_weight,
                observed_rate_tokens_per_minute,
                sample_count,
                active_minutes,
                last_sample_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(bucket_key) DO UPDATE SET
                provider_code = excluded.provider_code,
                model_bucket = excluded.model_bucket,
                effective_weight = excluded.effective_weight,
                observed_rate_tokens_per_minute = excluded.observed_rate_tokens_per_minute,
                sample_count = excluded.sample_count,
                active_minutes = excluded.active_minutes,
                last_sample_at = excluded.last_sample_at,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(bucketKey),
                .text(provider.rawValue),
                .text(modelBucket),
                .double(effectiveWeight),
                .double(observedRateTokensPerMinute),
                .integer(sampleCount),
                .double(activeMinutes),
                .text(lastSampleAt),
                .text(now),
            ]
        )
    }

    private static func bucketKey(provider: ProviderCode, modelSlug: String?) -> String {
        "\(provider.rawValue):\(modelBucket(from: modelSlug))"
    }

    private static func modelBucket(from modelSlug: String?) -> String {
        guard let modelSlug else {
            return "unknown"
        }
        let normalized = modelSlug
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { $0.isEmpty == false }
            .joined(separator: "-")
        return normalized.isEmpty ? "unknown" : normalized
    }

    private static func providerFallbackWeight(_ provider: ProviderCode) -> Double {
        switch provider {
        case .claude:
            return 1.00
        case .codex:
            return 0.15
        case .gemini:
            return 0.35
        case .cursor:
            return 0.50
        case .openclaw:
            return 0.15
        }
    }

    private static func updatedObservedRate(
        previousRate: Double,
        intervalMinutes: Double?,
        rawDeltaTokens: Int64
    ) -> Double {
        guard let intervalMinutes, intervalMinutes > 0 else {
            return previousRate
        }
        let currentRate = Double(rawDeltaTokens) / intervalMinutes
        guard previousRate > 0 else {
            return currentRate
        }
        return (previousRate * smoothingPreviousWeight) + (currentRate * smoothingNewWeight)
    }

    private static func activeIntervalMinutes(
        previousObservedAt: String?,
        currentObservedAt: String
    ) -> Double? {
        guard let previousObservedAt,
              let previousDate = parseTimestamp(previousObservedAt),
              let currentDate = parseTimestamp(currentObservedAt) else {
            return nil
        }
        let rawMinutes = currentDate.timeIntervalSince(previousDate) / 60.0
        guard rawMinutes > 0 else {
            return nil
        }
        return clamp(rawMinutes, minimumIntervalMinutes, maximumIntervalMinutes)
    }

    private static func softCappedDelta(_ weightedDelta: Double) -> (Int64, Bool) {
        let capped: Double
        let softCapApplied: Bool
        if weightedDelta <= softCapThresholdTokens {
            capped = weightedDelta
            softCapApplied = false
        } else {
            capped = softCapThresholdTokens
                + ((weightedDelta - softCapThresholdTokens) * softCapOverflowMultiplier)
            softCapApplied = true
        }
        return (max(1, Int64(capped.rounded(.toNearestOrAwayFromZero))), softCapApplied)
    }

    private static func savePacingMultiplier(database: SQLiteDatabase) throws -> Double {
        let seed = try gameplayBalanceSeed(database: database)
        let hash = stableHash(seed)
        let unit = Double(hash % 10_001) / 10_000.0
        return 0.92 + (unit * 0.16)
    }

    private static func gameplayBalanceSeed(database: SQLiteDatabase) throws -> String {
        if let existing = try database.fetchOne(
            """
            SELECT setting_value_json
            FROM settings
            WHERE setting_key = ?
            LIMIT 1;
            """,
            bindings: [.text(seedSettingKey)],
            map: { statement in
                SQLiteDatabase.columnText(statement, index: 0)
            }
        ) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(String.self, from: Data(existing.utf8)),
               decoded.isEmpty == false {
                return decoded
            }
        }

        let seed = UUID().uuidString.lowercased()
        let now = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO settings (
                setting_key,
                setting_value_json,
                updated_at
            ) VALUES (?, ?, ?)
            ON CONFLICT(setting_key) DO NOTHING;
            """,
            bindings: [
                .text(seedSettingKey),
                .text("\"\(seed)\""),
                .text(now),
            ]
        )
        return seed
    }

    private static func parseTimestamp(_ rawValue: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return precise.date(from: rawValue) ?? standard.date(from: rawValue)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }

    private static func clamp(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
