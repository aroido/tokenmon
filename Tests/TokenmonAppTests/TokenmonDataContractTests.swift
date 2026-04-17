import Foundation
import Testing
@testable import TokenmonGameEngine
@testable import TokenmonPersistence
import TokenmonDomain
import TokenmonProviders

struct TokenmonDataContractTests {
    @Test
    func approvedPortraitSourceCoversAllSpeciesAssetKeys() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let batchRoot = repoRoot.appendingPathComponent("art/source/species/approved-portraits", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: batchRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var assetKeys = Set<String>()
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "png" else {
                continue
            }
            assetKeys.insert(url.deletingPathExtension().lastPathComponent)
        }

        let expected = Set(SpeciesCatalog.all.map(\.assetKey))
        #expect(assetKeys.count == SpeciesCatalog.expectedCount)
        #expect(assetKeys == expected)
    }

    @Test
    func fieldTypesExposeCanonicalIceOrder() {
        #expect(FieldType.allCases == [.grassland, .ice, .coast, .sky])
        #expect(FieldType(rawValue: "ice") == .ice)
        #expect(FieldType(rawValue: "underground") == nil)
    }

    @Test
    func speciesCatalogUsesIceRoster() {
        let iceSpecies = SpeciesCatalog.all.filter { $0.field == .ice }

        #expect(iceSpecies.count == 37)
        #expect(iceSpecies.first?.id == "ICE_001")
        #expect(iceSpecies.first?.name == "Snowmole")
        #expect(iceSpecies.last?.id == "ICE_037")
        #expect(iceSpecies.last?.name == "Whiteout Titan")
        #expect(iceSpecies.contains { $0.assetKey == "ice_021_aurora_lynx" })
        #expect(!SpeciesCatalog.all.contains { $0.id.hasPrefix("UND_") })
    }

    @Test
    func encounterGenerationUsesIceFieldWeights() {
        let config = EncounterGenerationConfig()

        #expect(config.baseFieldWeights[.grassland] == 32)
        #expect(config.baseFieldWeights[.ice] == 20)
        #expect(config.baseFieldWeights[.coast] == 24)
        #expect(config.baseFieldWeights[.sky] == 24)
    }

    @Test
    func encounterGenerationUsesRebalancedDefaultRarityWeights() {
        let config = EncounterGenerationConfig()

        #expect(config.baseRarityWeights[.common] == 54)
        #expect(config.baseRarityWeights[.uncommon] == 28)
        #expect(config.baseRarityWeights[.rare] == 11)
        #expect(config.baseRarityWeights[.epic] == 5)
        #expect(config.baseRarityWeights[.legendary] == 2)
    }

    @Test
    func captureResolverUsesRebalancedDefaultOdds() throws {
        let resolver = CaptureResolver()

        #expect(try resolver.captureProbability(for: .common) == 0.88)
        #expect(try resolver.captureProbability(for: .uncommon) == 0.68)
        #expect(try resolver.captureProbability(for: .rare) == 0.36)
        #expect(try resolver.captureProbability(for: .epic) == 0.16)
        #expect(try resolver.captureProbability(for: .legendary) == 0.06)
    }

    @Test
    func explorationAccumulatorUsesRebalancedThresholdRange() {
        let config = ExplorationAccumulatorConfig()

        #expect(config.minimumEncounterThresholdTokens == 18_000_000)
        #expect(config.maximumEncounterThresholdTokens == 22_000_000)
    }

    @Test
    func appSettingsRoundTripKeepsAppearanceAndPresentationPreferences() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let defaults = try manager.appSettings()
        #expect(defaults.fieldBackplateEnabled)
        #expect(!defaults.updateNotificationsEnabled)
        #expect(defaults.appearancePreference == .system)
        #expect(defaults.languagePreference == .system)
        #expect(!defaults.firstRunSetupPromptShown)
        #expect(!defaults.usageAnalyticsEnabled)
        #expect(!defaults.usageAnalyticsPromptDismissed)

        var updated = defaults
        updated.notificationsEnabled = false
        updated.updateNotificationsEnabled = true
        updated.firstRunSetupPromptShown = true
        updated.fieldBackplateEnabled = false
        updated.usageAnalyticsEnabled = true
        updated.usageAnalyticsPromptDismissed = true
        updated.appearancePreference = .dark
        updated.languagePreference = .korean
        try manager.saveAppSettings(updated)

        let reloaded = try manager.appSettings()
        #expect(!reloaded.notificationsEnabled)
        #expect(reloaded.updateNotificationsEnabled)
        #expect(reloaded.firstRunSetupPromptShown)
        #expect(!reloaded.fieldBackplateEnabled)
        #expect(reloaded.usageAnalyticsEnabled)
        #expect(reloaded.usageAnalyticsPromptDismissed)
        #expect(reloaded.appearancePreference == .dark)
        #expect(reloaded.languagePreference == .korean)
        #expect(reloaded.providerStatusVisibility == defaults.providerStatusVisibility)
        #expect(reloaded.launchAtLogin == defaults.launchAtLogin)
    }

    @Test
    func analyticsInstallationIDPersistsAcrossReads() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-analytics-install-id-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let firstID = try manager.analyticsInstallationID()
        let secondID = try manager.analyticsInstallationID()

        #expect(firstID == secondID)
        #expect(!firstID.isEmpty)
    }

    @Test
    func resetDexProgressClearsDexTablesAndKeepsEncounterAndUsageHistory() throws {
        let manager = try makeManager(prefix: "tokenmon-reset-dex")
        let database = try manager.open()
        try seedDeveloperToolMutationState(database: database)

        try manager.resetDexProgress()

        let dexSeenCount = try rowCount(in: "dex_seen", database: database)
        let dexCapturedCount = try rowCount(in: "dex_captured", database: database)
        let encounterCount = try rowCount(in: "encounters", database: database)
        let usageSampleCount = try rowCount(in: "usage_samples", database: database)
        let dexEventCount = try database.fetchOne(
            """
            SELECT COUNT(*)
            FROM domain_events
            WHERE event_type IN ('seen_dex_updated', 'captured_dex_updated');
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        let progressEventCount = try database.fetchOne(
            """
            SELECT COUNT(*)
            FROM domain_events
            WHERE event_type = 'exploration_progress_updated';
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        let summary = try manager.summary()
        let currentRunSummary = try manager.currentRunSummary()

        #expect(dexSeenCount == 0)
        #expect(dexCapturedCount == 0)
        #expect(encounterCount == 1)
        #expect(usageSampleCount == 1)
        #expect(dexEventCount == 0)
        #expect(progressEventCount == 1)
        #expect(summary.totalCaptures == 1)
        #expect(currentRunSummary.capturedSpeciesCount == 0)
    }

    @Test
    func resetEncounterHistoryClearsEncounterStateAndKeepsUsageSamples() throws {
        let manager = try makeManager(prefix: "tokenmon-reset-encounters")
        let database = try manager.open()
        try seedDeveloperToolMutationState(database: database)

        try manager.resetEncounterHistory()

        let encounterCount = try rowCount(in: "encounters", database: database)
        let dexSeenCount = try rowCount(in: "dex_seen", database: database)
        let dexCapturedCount = try rowCount(in: "dex_captured", database: database)
        let usageSampleCount = try rowCount(in: "usage_samples", database: database)
        let encounterEventCount = try database.fetchOne(
            """
            SELECT COUNT(*)
            FROM domain_events
            WHERE event_type IN (
                'encounter_threshold_crossed',
                'field_selected',
                'rarity_selected',
                'species_selected',
                'encounter_spawned',
                'capture_resolved',
                'seen_dex_updated',
                'captured_dex_updated'
            );
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        let summary = try manager.summary()

        #expect(encounterCount == 0)
        #expect(dexSeenCount == 0)
        #expect(dexCapturedCount == 0)
        #expect(usageSampleCount == 1)
        #expect(encounterEventCount == 0)
        #expect(summary.totalNormalizedTokens == 6_200)
        #expect(summary.totalEncounters == 0)
        #expect(summary.totalCaptures == 0)
        #expect(summary.tokensSinceLastEncounter == 0)
        #expect(summary.nextEncounterThresholdTokens == ExplorationAccumulatorConfig().tokensRequiredForEncounter(1))
    }

    @Test
    func makeNextEncounterReadySetsProgressOneShortOfThreshold() throws {
        let manager = try makeManager(prefix: "tokenmon-next-encounter")
        let database = try manager.open()
        try seedDeveloperToolMutationState(database: database)

        try manager.makeNextEncounterReady()

        let summary = try manager.summary()
        let state = try manager.explorationState()

        #expect(summary.tokensSinceLastEncounter == summary.nextEncounterThresholdTokens - 1)
        #expect(state.tokensSinceLastEncounter == state.nextEncounterThresholdTokens - 1)
    }

    @Test
    func applyExplorationOverridePersistsExplicitProgress() throws {
        let manager = try makeManager(prefix: "tokenmon-exploration-override")

        try manager.applyExplorationOverride(
            totalNormalizedTokens: 9_900,
            tokensSinceLastEncounter: 499,
            nextEncounterThresholdTokens: 700
        )

        let summary = try manager.summary()

        #expect(summary.totalNormalizedTokens == 9_900)
        #expect(summary.tokensSinceLastEncounter == 499)
        #expect(summary.nextEncounterThresholdTokens == 700)
        #expect(summary.tokensUntilNextEncounter == 201)
    }

    @Test
    func applyTotalsOverrideRejectsCapturesAboveEncounters() throws {
        let manager = try makeManager(prefix: "tokenmon-totals-override")

        do {
            try manager.applyTotalsOverride(totalEncounters: 3, totalCaptures: 4)
            Issue.record("Expected totals override to reject captures above encounters")
        } catch let error as TokenmonDeveloperToolsMutationError {
            switch error {
            case let .invalidCaptureTotals(totalEncounters, totalCaptures):
                #expect(totalEncounters == 3)
                #expect(totalCaptures == 4)
            default:
                Issue.record("Unexpected mutation error: \(error.localizedDescription)")
            }
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    func migrationVersionThreeResetsProgressAndSeedsIceCatalog() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()
        let originalStartedAt = try manager.summary().gameplayStartedAt

        let database = try manager.open()
        try database.inTransaction {
            try database.execute("DROP TABLE exploration_state;")
            try database.execute(
                """
                CREATE TABLE exploration_state (
                    exploration_state_id INTEGER PRIMARY KEY NOT NULL,
                    total_normalized_tokens INTEGER NOT NULL,
                    pending_tokens INTEGER NOT NULL CHECK(pending_tokens >= 0),
                    total_steps INTEGER NOT NULL,
                    steps_since_last_encounter INTEGER NOT NULL CHECK(steps_since_last_encounter >= 0),
                    total_encounters INTEGER NOT NULL,
                    total_captures INTEGER NOT NULL,
                    last_usage_sample_id INTEGER REFERENCES usage_samples(usage_sample_id),
                    updated_at TEXT NOT NULL
                );
                """
            )
            try database.execute(
                """
                INSERT INTO exploration_state (
                    exploration_state_id,
                    total_normalized_tokens,
                    pending_tokens,
                    total_steps,
                    steps_since_last_encounter,
                    total_encounters,
                    total_captures,
                    last_usage_sample_id,
                    updated_at
                ) VALUES (1, 0, 0, 0, 0, 0, 0, NULL, '2026-01-01T00:00:00Z');
                """
            )
            try database.execute("PRAGMA user_version = 2;")
            try database.execute("DELETE FROM species;")
            try database.execute(
                """
                INSERT INTO species (
                    species_id,
                    name,
                    field_code,
                    rarity_tier,
                    is_active,
                    sort_order,
                    asset_key,
                    flavor_text,
                    introduced_in_version,
                    created_at
                ) VALUES (?, ?, ?, ?, 1, 115, ?, NULL, '0.1.0', '2026-01-01T00:00:00Z');
                """,
                bindings: [
                    .text("UND_001"),
                    .text("Dustmole"),
                    .text("underground"),
                    .text("common"),
                    .text("und_001_dustmole"),
                ]
            )
            try database.execute(
                """
                UPDATE exploration_state
                SET total_normalized_tokens = 500,
                    pending_tokens = 120,
                    total_steps = 7,
                    steps_since_last_encounter = 3,
                    total_encounters = 2,
                    total_captures = 1,
                    updated_at = '2026-01-01T00:00:00Z'
                WHERE exploration_state_id = 1;
                """
            )
            try database.execute(
                """
                INSERT INTO settings (
                    setting_key,
                    setting_value_json,
                    updated_at
                ) VALUES ('ui_test_setting', 'true', '2026-01-01T00:00:00Z')
                ON CONFLICT(setting_key) DO UPDATE SET
                    setting_value_json = excluded.setting_value_json,
                    updated_at = excluded.updated_at;
                """
            )
        }

        _ = try manager.open()
        let summary = try manager.summary()
        let migratedDatabase = try manager.open()

        let customSetting = try migratedDatabase.fetchOne(
            """
            SELECT setting_value_json
            FROM settings
            WHERE setting_key = 'ui_test_setting'
            LIMIT 1;
            """
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        let iceSpeciesCount = try migratedDatabase.fetchOne(
            "SELECT COUNT(*) FROM species WHERE species_id = 'ICE_001';"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        let undergroundSpeciesCount = try migratedDatabase.fetchOne(
            "SELECT COUNT(*) FROM species WHERE species_id = 'UND_001';"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0

        #expect(summary.totalNormalizedTokens == 0)
        #expect(summary.tokensSinceLastEncounter == 0)
        #expect(summary.nextEncounterThresholdTokens > 0)
        #expect(summary.totalEncounters == 0)
        #expect(summary.totalCaptures == 0)
        #expect(summary.gameplayStartedAt != originalStartedAt)
        #expect(customSetting == "true")
        #expect(iceSpeciesCount == 1)
        #expect(undergroundSpeciesCount == 0)
    }

    @Test
    func migrationVersionFourHealsVersionThreeDatabasesWithUndergroundRows() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-migration-v4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()
        let database = try manager.open()
        let originalStartedAt = try manager.summary().gameplayStartedAt

        try database.execute("PRAGMA foreign_keys = OFF;")
        try database.inTransaction {
            try database.execute("DROP TABLE exploration_state;")
            try database.execute(
                """
                CREATE TABLE exploration_state (
                    exploration_state_id INTEGER PRIMARY KEY NOT NULL,
                    total_normalized_tokens INTEGER NOT NULL,
                    pending_tokens INTEGER NOT NULL CHECK(pending_tokens >= 0),
                    total_steps INTEGER NOT NULL,
                    steps_since_last_encounter INTEGER NOT NULL CHECK(steps_since_last_encounter >= 0),
                    total_encounters INTEGER NOT NULL,
                    total_captures INTEGER NOT NULL,
                    last_usage_sample_id INTEGER REFERENCES usage_samples(usage_sample_id),
                    updated_at TEXT NOT NULL
                );
                """
            )
            try database.execute(
                """
                INSERT INTO exploration_state (
                    exploration_state_id,
                    total_normalized_tokens,
                    pending_tokens,
                    total_steps,
                    steps_since_last_encounter,
                    total_encounters,
                    total_captures,
                    last_usage_sample_id,
                    updated_at
                ) VALUES (1, 0, 0, 0, 0, 0, 0, NULL, '2026-01-01T00:00:00Z');
                """
            )
            try database.execute("PRAGMA user_version = 3;")
            try database.execute("DELETE FROM species;")
            try database.execute(
                """
                INSERT INTO species (
                    species_id,
                    name,
                    field_code,
                    rarity_tier,
                    is_active,
                    sort_order,
                    asset_key,
                    flavor_text,
                    introduced_in_version,
                    created_at
                ) VALUES (?, ?, ?, ?, 1, 115, ?, NULL, '0.1.0', '2026-01-01T00:00:00Z');
                """,
                bindings: [
                    .text("UND_001"),
                    .text("Dustmole"),
                    .text("underground"),
                    .text("common"),
                    .text("und_001_dustmole"),
                ]
            )
            try database.execute(
                """
                INSERT INTO encounters (
                    encounter_id,
                    encounter_sequence,
                    provider_code,
                    provider_session_row_id,
                    usage_sample_id,
                    threshold_event_index,
                    occurred_at,
                    field_code,
                    rarity_tier,
                    species_id,
                    burst_intensity_band,
                    capture_probability,
                    capture_roll,
                    outcome,
                    created_at
                ) VALUES (
                    'legacy-encounter',
                    1,
                    NULL,
                    NULL,
                    1,
                    1,
                    '2026-01-01T00:00:00Z',
                    'underground',
                    'common',
                    'UND_001',
                    1,
                    0.5,
                    0.2,
                    'captured',
                    '2026-01-01T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO dex_seen (
                    species_id,
                    first_seen_at,
                    last_seen_at,
                    seen_count,
                    last_encounter_id,
                    updated_at
                ) VALUES (
                    'UND_001',
                    '2026-01-01T00:00:00Z',
                    '2026-01-01T00:00:00Z',
                    1,
                    'legacy-encounter',
                    '2026-01-01T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO dex_captured (
                    species_id,
                    first_captured_at,
                    last_captured_at,
                    captured_count,
                    last_encounter_id,
                    updated_at
                ) VALUES (
                    'UND_001',
                    '2026-01-01T00:00:00Z',
                    '2026-01-01T00:00:00Z',
                    1,
                    'legacy-encounter',
                    '2026-01-01T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                UPDATE exploration_state
                SET total_normalized_tokens = 900,
                    pending_tokens = 50,
                    total_steps = 9,
                    steps_since_last_encounter = 2,
                    total_encounters = 1,
                    total_captures = 1,
                    updated_at = '2026-01-01T00:00:00Z'
                WHERE exploration_state_id = 1;
                """
            )
        }
        try database.execute("PRAGMA foreign_keys = ON;")

        _ = try manager.open()
        let summary = try manager.summary()
        let healedDatabase = try manager.open()

        let undergroundSpeciesCount = try healedDatabase.fetchOne(
            "SELECT COUNT(*) FROM species WHERE field_code = 'underground' OR species_id LIKE 'UND_%';"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        let undergroundEncounterCount = try healedDatabase.fetchOne(
            "SELECT COUNT(*) FROM encounters WHERE field_code = 'underground' OR species_id LIKE 'UND_%';"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0

        #expect(summary.species == SpeciesCatalog.expectedCount)
        #expect(summary.totalNormalizedTokens == 0)
        #expect(summary.tokensSinceLastEncounter == 0)
        #expect(summary.totalEncounters == 0)
        #expect(summary.totalCaptures == 0)
        #expect(summary.gameplayStartedAt != originalStartedAt)
        #expect(undergroundSpeciesCount == 0)
        #expect(undergroundEncounterCount == 0)
    }

    @Test
    func migrationVersionFiveConvertsLegacyStepProgressIntoTokenProgress() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-migration-v5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()
        try database.inTransaction {
            try database.execute("DROP TABLE exploration_state;")
            try database.execute(
                """
                CREATE TABLE exploration_state (
                    exploration_state_id INTEGER PRIMARY KEY NOT NULL,
                    total_normalized_tokens INTEGER NOT NULL,
                    pending_tokens INTEGER NOT NULL CHECK(pending_tokens >= 0),
                    total_steps INTEGER NOT NULL,
                    steps_since_last_encounter INTEGER NOT NULL CHECK(steps_since_last_encounter >= 0),
                    total_encounters INTEGER NOT NULL,
                    total_captures INTEGER NOT NULL,
                    last_usage_sample_id INTEGER REFERENCES usage_samples(usage_sample_id),
                    updated_at TEXT NOT NULL
                );
                """
            )
            try database.execute(
                """
                INSERT INTO exploration_state (
                    exploration_state_id,
                    total_normalized_tokens,
                    pending_tokens,
                    total_steps,
                    steps_since_last_encounter,
                    total_encounters,
                    total_captures,
                    last_usage_sample_id,
                    updated_at
                ) VALUES (
                    1,
                    12_345_600,
                    50,
                    61_728,
                    3,
                    2,
                    1,
                    NULL,
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute("PRAGMA user_version = 4;")
        }

        _ = try manager.open()
        let summary = try manager.summary()
        let state = try manager.explorationState()
        let expectedNextThreshold = ExplorationAccumulatorConfig().tokensRequiredForEncounter(3)

        #expect(summary.totalNormalizedTokens == 12_345_600)
        #expect(summary.tokensSinceLastEncounter == 650)
        #expect(summary.nextEncounterThresholdTokens == expectedNextThreshold)
        #expect(summary.tokensUntilNextEncounter == expectedNextThreshold - 650)
        #expect(summary.totalEncounters == 2)
        #expect(summary.totalCaptures == 1)
        #expect(state.tokensSinceLastEncounter == 650)
        #expect(state.nextEncounterThresholdTokens == expectedNextThreshold)
    }

    @Test
    func todayActivitySummaryCountsOnlyTodayEncounters() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-today-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()
        // Insert two captures and one escape today, one capture yesterday.
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let nowStamp = formatter.string(from: now)
        let yesterdayStamp = formatter.string(from: yesterday)

        try database.execute("PRAGMA foreign_keys = OFF;")
        for (index, payload) in [
            ("today-1", nowStamp, "captured"),
            ("today-2", nowStamp, "captured"),
            ("today-3", nowStamp, "escaped"),
            ("yesterday-1", yesterdayStamp, "captured"),
        ].enumerated() {
            try database.execute(
                """
                INSERT INTO encounters (
                    encounter_id, encounter_sequence, provider_code, provider_session_row_id,
                    usage_sample_id, threshold_event_index, occurred_at, field_code,
                    rarity_tier, species_id, burst_intensity_band, capture_probability,
                    capture_roll, outcome, created_at
                ) VALUES (?, ?, NULL, NULL, 1, ?, ?, 'grassland', 'common',
                          'GRS_001', 1, 0.5, 0.2, ?, ?);
                """,
                bindings: [
                    .text(payload.0),
                    .integer(Int64(index + 1)),
                    .integer(Int64(index + 1)),
                    .text(payload.1),
                    .text(payload.2),
                    .text(payload.1),
                ]
            )
        }
        try database.execute("PRAGMA foreign_keys = ON;")

        let summary = try manager.todayActivitySummary()

        #expect(summary.encounterCount == 3)
        #expect(summary.captureCount == 2)
    }

    @Test
    func encounterFieldDistributionGroupsByFieldCode() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-fielddist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()
        try database.execute("PRAGMA foreign_keys = OFF;")
        let inserts: [(String, String, Int64)] = [
            ("g1", "grassland", 1),
            ("g2", "grassland", 2),
            ("g3", "grassland", 3),
            ("c1", "coast", 4),
            ("s1", "sky", 5),
            ("s2", "sky", 6),
        ]
        for (id, field, seq) in inserts {
            try database.execute(
                """
                INSERT INTO encounters (
                    encounter_id, encounter_sequence, provider_code, provider_session_row_id,
                    usage_sample_id, threshold_event_index, occurred_at, field_code,
                    rarity_tier, species_id, burst_intensity_band, capture_probability,
                    capture_roll, outcome, created_at
                ) VALUES (?, ?, NULL, NULL, 1, ?, '2026-04-08T00:00:00Z', ?, 'common',
                          'GRS_001', 1, 0.5, 0.2, 'captured', '2026-04-08T00:00:00Z');
                """,
                bindings: [.text(id), .integer(seq), .integer(seq), .text(field)]
            )
        }
        try database.execute("PRAGMA foreign_keys = ON;")

        let distribution = try manager.encounterFieldDistribution()

        #expect(distribution[.grassland] == 3)
        #expect(distribution[.coast] == 1)
        #expect(distribution[.sky] == 2)
        #expect(distribution[.ice] == nil || distribution[.ice] == 0)
    }

    @Test
    func encounterDailyTrendReturnsExactlySevenBucketsZeroFilled() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-trend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()
        try database.execute("PRAGMA foreign_keys = OFF;")
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let calendar = Calendar.current

        // Insert: today -> 2 captured, 1 escaped. 3 days ago -> 1 captured. 9 days ago -> 1 captured (out of window).
        let entries: [(daysAgo: Int, outcome: String)] = [
            (0, "captured"), (0, "captured"), (0, "escaped"),
            (3, "captured"),
            (9, "captured"),
        ]
        for (index, entry) in entries.enumerated() {
            let stamp = formatter.string(from: calendar.date(byAdding: .day, value: -entry.daysAgo, to: now)!)
            try database.execute(
                """
                INSERT INTO encounters (
                    encounter_id, encounter_sequence, provider_code, provider_session_row_id,
                    usage_sample_id, threshold_event_index, occurred_at, field_code,
                    rarity_tier, species_id, burst_intensity_band, capture_probability,
                    capture_roll, outcome, created_at
                ) VALUES (?, ?, NULL, NULL, 1, ?, ?, 'grassland', 'common',
                          'GRS_001', 1, 0.5, 0.2, ?, ?);
                """,
                bindings: [
                    .text("trend-\(index)"),
                    .integer(Int64(index + 1)),
                    .integer(Int64(index + 1)),
                    .text(stamp),
                    .text(entry.outcome),
                    .text(stamp),
                ]
            )
        }
        try database.execute("PRAGMA foreign_keys = ON;")

        let buckets = try manager.encounterDailyTrend(days: 7)

        #expect(buckets.count == 7)
        // Oldest first, newest (today) last.
        #expect(buckets.last?.captures == 2)
        #expect(buckets.last?.escapes == 1)

        let threeDaysAgoBucket = buckets[buckets.count - 4]
        #expect(threeDaysAgoBucket.captures == 1)
        #expect(threeDaysAgoBucket.escapes == 0)

        // The 9-days-ago entry must NOT appear.
        let totalCaptures = buckets.reduce(0) { $0 + $1.captures }
        #expect(totalCaptures == 3)
    }

    private func makeManager(prefix: String) throws -> TokenmonDatabaseManager {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()
        return manager
    }

    private func rowCount(in table: String, database: SQLiteDatabase) throws -> Int64 {
        try database.fetchOne("SELECT COUNT(*) FROM \(table);") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
    }

    private func seedDeveloperToolMutationState(database: SQLiteDatabase) throws {
        try database.inTransaction {
            try database.execute(
                """
                INSERT INTO provider_sessions (
                    provider_session_row_id,
                    provider_code,
                    provider_session_id,
                    session_identity_kind,
                    source_mode,
                    model_slug,
                    workspace_dir,
                    transcript_path,
                    started_at,
                    ended_at,
                    last_seen_at,
                    session_state,
                    created_at,
                    updated_at
                ) VALUES (
                    1,
                    'codex',
                    'developer-session',
                    'provider_session_id',
                    'codex_exec_json',
                    'gpt-5.4',
                    '/tmp/tokenmon-tests',
                    NULL,
                    '2026-04-08T00:00:00Z',
                    NULL,
                    '2026-04-08T00:00:00Z',
                    'active',
                    '2026-04-08T00:00:00Z',
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO ingest_sources (
                    ingest_source_id,
                    source_key,
                    source_kind,
                    source_path,
                    last_offset,
                    last_line_number,
                    last_event_fingerprint,
                    last_seen_at,
                    updated_at
                ) VALUES (
                    1,
                    'codex:developer-session',
                    'inbox_file',
                    '/tmp/tokenmon-tests/Inbox/codex.ndjson',
                    0,
                    0,
                    'fingerprint-1',
                    '2026-04-08T00:00:00Z',
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO provider_ingest_events (
                    provider_ingest_event_id,
                    provider_code,
                    source_mode,
                    provider_session_row_id,
                    ingest_source_id,
                    provider_event_fingerprint,
                    raw_reference_kind,
                    raw_reference_event_name,
                    raw_reference_offset,
                    observed_at,
                    payload_json,
                    acceptance_state,
                    rejection_reason,
                    created_at
                ) VALUES (
                    1,
                    'codex',
                    'codex_exec_json',
                    1,
                    1,
                    'fingerprint-1',
                    'jsonl',
                    'turn.completed',
                    '1',
                    '2026-04-08T00:00:00Z',
                    '{}',
                    'accepted',
                    NULL,
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO usage_samples (
                    usage_sample_id,
                    provider_ingest_event_id,
                    provider_code,
                    provider_session_row_id,
                    observed_at,
                    total_input_tokens,
                    total_output_tokens,
                    total_cached_input_tokens,
                    normalized_total_tokens,
                    normalized_delta_tokens,
                    current_input_tokens,
                    current_output_tokens,
                    burst_intensity_band,
                    created_at
                ) VALUES (
                    1,
                    1,
                    'codex',
                    1,
                    '2026-04-08T00:00:00Z',
                    4200,
                    1600,
                    400,
                    6200,
                    6200,
                    4200,
                    1600,
                    2,
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                UPDATE exploration_state
                SET total_normalized_tokens = 6200,
                    tokens_since_last_encounter = 1200,
                    next_encounter_threshold_tokens = 5500,
                    total_encounters = 1,
                    total_captures = 1,
                    last_usage_sample_id = 1,
                    updated_at = '2026-04-08T00:00:00Z'
                WHERE exploration_state_id = 1;
                """
            )
            try database.execute(
                """
                INSERT INTO encounters (
                    encounter_id,
                    encounter_sequence,
                    provider_code,
                    provider_session_row_id,
                    usage_sample_id,
                    threshold_event_index,
                    occurred_at,
                    field_code,
                    rarity_tier,
                    species_id,
                    burst_intensity_band,
                    capture_probability,
                    capture_roll,
                    outcome,
                    created_at
                ) VALUES (
                    'encounter-1',
                    1,
                    'codex',
                    1,
                    1,
                    1,
                    '2026-04-08T00:00:00Z',
                    'grassland',
                    'common',
                    'GRS_001',
                    2,
                    0.5,
                    0.3,
                    'captured',
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO dex_seen (
                    species_id,
                    first_seen_at,
                    last_seen_at,
                    seen_count,
                    last_encounter_id,
                    updated_at
                ) VALUES (
                    'GRS_001',
                    '2026-04-08T00:00:00Z',
                    '2026-04-08T00:00:00Z',
                    1,
                    'encounter-1',
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO dex_captured (
                    species_id,
                    first_captured_at,
                    last_captured_at,
                    captured_count,
                    last_encounter_id,
                    updated_at
                ) VALUES (
                    'GRS_001',
                    '2026-04-08T00:00:00Z',
                    '2026-04-08T00:00:00Z',
                    1,
                    'encounter-1',
                    '2026-04-08T00:00:00Z'
                );
                """
            )
            try database.execute(
                """
                INSERT INTO domain_events (
                    event_id,
                    event_type,
                    occurred_at,
                    producer,
                    correlation_id,
                    causation_id,
                    aggregate_type,
                    aggregate_id,
                    payload_json,
                    created_at
                ) VALUES
                    ('event-usage', 'usage_sample_recorded', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'provider_session', 'codex:developer-session', '{}', '2026-04-08T00:00:00Z'),
                    ('event-progress', 'exploration_progress_updated', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'exploration_state', '1', '{}', '2026-04-08T00:00:00Z'),
                    ('event-threshold', 'encounter_threshold_crossed', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'exploration_state', '1', '{}', '2026-04-08T00:00:00Z'),
                    ('event-seen', 'seen_dex_updated', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'dex_seen', 'GRS_001', '{}', '2026-04-08T00:00:00Z'),
                    ('event-captured', 'captured_dex_updated', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'dex_captured', 'GRS_001', '{}', '2026-04-08T00:00:00Z'),
                    ('event-spawned', 'encounter_spawned', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'encounter', 'encounter-1', '{}', '2026-04-08T00:00:00Z'),
                    ('event-resolved', 'capture_resolved', '2026-04-08T00:00:00Z', 'tests', NULL, NULL, 'encounter', 'encounter-1', '{}', '2026-04-08T00:00:00Z');
                """
            )
        }
    }

    @Test
    func providerCodeIncludesGeminiWithExpectedMetadata() {
        #expect(ProviderCode.allCases.contains(.gemini))
        #expect(ProviderCode(rawValue: "gemini") == .gemini)
        #expect(ProviderCode.gemini.displayName == "Gemini CLI")
        #expect(ProviderCode.gemini.defaultSupportLevel == "first_class")
    }

    @Test
    func migrationVersionSixSeedsGeminiProviderRow() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-mig-v6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()

        // Wind the schema back to v5 and remove the gemini row to simulate a
        // pre-v6 database. Bootstrap re-seed of providers is suppressed by
        // pretending we are at version 5 and forcing a downgrade.
        try database.execute("PRAGMA user_version = 5;")
        try database.execute("DELETE FROM providers WHERE provider_code = 'gemini';")

        // Re-open to trigger migrations.
        _ = try manager.open()

        let count = try database.fetchOne(
            "SELECT COUNT(*) FROM providers WHERE provider_code = 'gemini';"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0

        #expect(count == 1)

        let displayName = try database.fetchOne(
            "SELECT display_name FROM providers WHERE provider_code = 'gemini';"
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        #expect(displayName == "Gemini CLI")
    }

    @Test
    func migrationVersionSevenRebuildsUsageSamplesOutsideTransactionWhenEncountersReferenceThem() throws {
        let manager = try makeManager(prefix: "tokenmon-mig-v7")
        let database = try manager.open()
        try seedDeveloperToolMutationState(database: database)

        try database.execute("PRAGMA user_version = 6;")

        _ = try manager.open()

        let version = try database.fetchOne("PRAGMA user_version;") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        let usageSampleCount = try rowCount(in: "usage_samples", database: database)
        let encounterCount = try rowCount(in: "encounters", database: database)
        let gameplayColumns = try database.fetchAll("PRAGMA table_info(usage_samples);") { statement in
            SQLiteDatabase.columnText(statement, index: 1)
        }

        #expect(version == 7)
        #expect(usageSampleCount == 1)
        #expect(encounterCount == 1)
        #expect(gameplayColumns.contains("gameplay_eligibility"))
        #expect(gameplayColumns.contains("gameplay_delta_tokens"))
    }

    @Test
    func dexEntrySummaryIncludesStatsAndTraits() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-dex-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let entries = try manager.dexEntrySummaries()
        guard let first = entries.first else {
            Issue.record("No entries returned")
            return
        }

        // After seeding, stats should have real values (not default all-1s)
        #expect(first.stats.total >= 12, "First species (Common) total should be at least 12")
        #expect(first.stats.traits.isEmpty == false, "First species should have at least 1 trait")
    }

    @Test
    func repeatedOpenDoesNotReseedProvidersOnceProcessBootstrapCompletes() throws {
        let manager = try makeManager(prefix: "tokenmon-bootstrap-cache")
        let database = try manager.open()

        let firstUpdatedAt = try database.fetchOne(
            "SELECT updated_at FROM providers WHERE provider_code = 'codex';"
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }

        Thread.sleep(forTimeInterval: 0.01)
        _ = try manager.open()

        let secondUpdatedAt = try database.fetchOne(
            "SELECT updated_at FROM providers WHERE provider_code = 'codex';"
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }

        #expect(firstUpdatedAt == secondUpdatedAt)
    }

    @Test
    func providerHealthSummariesPreferCodexLiveModeAndExposeRecoveryPolicy() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-codex-health-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:00:00Z")

        let database = try manager.open()
        try database.inTransaction {
            try database.execute(
                """
                INSERT INTO provider_sessions (
                    provider_session_row_id,
                    provider_code,
                    provider_session_id,
                    session_identity_kind,
                    source_mode,
                    model_slug,
                    workspace_dir,
                    transcript_path,
                    started_at,
                    ended_at,
                    last_seen_at,
                    session_state,
                    created_at,
                    updated_at
                ) VALUES
                    (1, 'codex', 'recovery-session', 'authoritative', 'codex_session_store_recovery', 'gpt-5.4', NULL, '/tmp/recovery.jsonl', '2026-04-10T09:30:00Z', NULL, '2026-04-10T10:12:00Z', 'active', '2026-04-10T10:12:00Z', '2026-04-10T10:12:00Z'),
                    (2, 'codex', 'live-session', 'authoritative', 'codex_session_store_live', 'gpt-5.4', NULL, '/tmp/live.jsonl', '2026-04-10T10:10:00Z', NULL, '2026-04-10T10:11:00Z', 'active', '2026-04-10T10:11:00Z', '2026-04-10T10:11:00Z');
                """
            )
            try database.execute(
                """
                INSERT INTO provider_ingest_events (
                    provider_ingest_event_id,
                    provider_code,
                    source_mode,
                    provider_session_row_id,
                    ingest_source_id,
                    provider_event_fingerprint,
                    raw_reference_kind,
                    raw_reference_event_name,
                    raw_reference_offset,
                    observed_at,
                    payload_json,
                    acceptance_state,
                    rejection_reason,
                    created_at
                ) VALUES
                    (1, 'codex', 'codex_session_store_recovery', 1, NULL, 'recovery-1', 'session_store_recovery', 'token_count', '1', '2026-04-10T10:12:00Z', '{}', 'accepted', NULL, '2026-04-10T10:12:00Z'),
                    (2, 'codex', 'codex_session_store_live', 2, NULL, 'live-1', 'session_store_live', 'token_count', '1', '2026-04-10T10:11:00Z', '{}', 'accepted', NULL, '2026-04-10T10:11:00Z');
                """
            )
            try database.execute(
                """
                INSERT INTO usage_samples (
                    usage_sample_id,
                    provider_ingest_event_id,
                    provider_code,
                    provider_session_row_id,
                    observed_at,
                    total_input_tokens,
                    total_output_tokens,
                    total_cached_input_tokens,
                    normalized_total_tokens,
                    normalized_delta_tokens,
                    current_input_tokens,
                    current_output_tokens,
                    gameplay_eligibility,
                    gameplay_delta_tokens,
                    burst_intensity_band,
                    created_at
                ) VALUES
                    (1, 1, 'codex', 1, '2026-04-10T10:12:00Z', 1000, 400, 100, 1500, 1500, 1000, 400, 'recovery_only', 0, 1, '2026-04-10T10:12:00Z'),
                    (2, 2, 'codex', 2, '2026-04-10T10:11:00Z', 2000, 800, 200, 3000, 1500, 1000, 400, 'eligible_live', 1500, 1, '2026-04-10T10:11:00Z');
                """
            )
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
                ) VALUES (
                    'codex',
                    'codex_session_store_recovery',
                    'connected',
                    'Codex startup recovery updated dashboard totals from local sessions',
                    '2026-04-10T10:12:00Z',
                    NULL,
                    NULL,
                    NULL,
                    '2026-04-10T10:12:00Z'
                );
                """
            )
        }

        let summaries = try manager.providerHealthSummaries()
        let codex = try #require(summaries.first(where: { $0.provider == .codex }))
        let claude = try #require(summaries.first(where: { $0.provider == .claude }))
        let gemini = try #require(summaries.first(where: { $0.provider == .gemini }))

        #expect(codex.sourceMode == "codex_session_store_live")
        #expect(codex.offlineDashboardRecovery == "automatic_supported")
        #expect(codex.liveGameplayArmed)
        #expect(claude.offlineDashboardRecovery == "known_transcript_only")
        #expect(claude.liveGameplayArmed == false)
        #expect(gemini.offlineDashboardRecovery == "unavailable")
    }

    @Test
    func geminiOtelInboxWriterAppendsValidProviderUsageSampleEvent() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-gemini-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let inboxPath = tempDirectory.appendingPathComponent("gemini.ndjson").path

        let event = GeminiSampleEvent(
            sessionID: "session-abc",
            observedAt: ISO8601DateFormatter().date(from: "2026-04-09T14:23:11Z")!,
            model: "gemini-2.5-pro",
            inputTokens: 1234,
            outputTokens: 567,
            cachedContentTokens: 0,
            thoughtsTokens: 0,
            toolTokens: 0,
            totalTokens: 1801,
            durationMs: 842
        )

        let writer = GeminiOtelInboxWriter(inboxPath: inboxPath)
        try writer.append(
            event: event,
            cumulativeInputTokens: 1234,
            cumulativeOutputTokens: 567,
            cumulativeCachedInputTokens: 0,
            cumulativeNormalizedTotalTokens: 1801
        )

        let contents = try String(contentsOfFile: inboxPath, encoding: .utf8)
        let line = contents.split(separator: "\n").first.map(String.init) ?? ""
        let data = Data(line.utf8)
        let decoded = try JSONDecoder().decode(ProviderUsageSampleEvent.self, from: data)
        try decoded.validate()

        #expect(decoded.eventType == "provider_usage_sample")
        #expect(decoded.provider == .gemini)
        #expect(decoded.sourceMode == "otel-inprocess")
        #expect(decoded.providerSessionID == "session-abc")
        #expect(decoded.modelSlug == "gemini-2.5-pro")
        #expect(decoded.totalInputTokens == 1234)
        #expect(decoded.totalOutputTokens == 567)
        #expect(decoded.normalizedTotalTokens == 1801)
        #expect(decoded.currentInputTokens == 1234)
        #expect(decoded.currentOutputTokens == 567)
        #expect(decoded.providerEventFingerprint == "gemini-otel:session-abc:2026-04-09T14:23:11Z:1801")
        #expect(decoded.rawReference.kind == "gemini-otel")
        #expect(decoded.rawReference.eventName == "gemini_cli.api_response")
    }

    @Test
    func latestGeminiSessionTotalsReturnsMonotonicMaxesForRecentSessions() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-gemini-totals-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()
        try database.execute("PRAGMA foreign_keys = OFF;")

        // Insert a Gemini provider session row plus three usage_samples whose
        // normalized_total_tokens grow monotonically.
        try database.execute(
            """
            INSERT INTO provider_sessions (
                provider_code, provider_session_id, session_identity_kind, source_mode,
                model_slug, workspace_dir, transcript_path, started_at, ended_at,
                last_seen_at, session_state, created_at, updated_at
            ) VALUES (
                'gemini', 'session-A', 'otel.session_id', 'otel-inprocess',
                'gemini-2.5-pro', NULL, NULL, '2026-04-09T10:00:00Z', NULL,
                '2026-04-09T13:00:00Z', 'active', '2026-04-09T10:00:00Z', '2026-04-09T13:00:00Z'
            );
            """
        )

        let sessionRowID = try database.fetchOne("SELECT last_insert_rowid();") { stmt in
            SQLiteDatabase.columnInt64(stmt, index: 0)
        } ?? 0

        let totalsByIndex: [(input: Int64, output: Int64, normalized: Int64, delta: Int64)] = [
            (50, 50, 100, 100),
            (125, 125, 250, 150),
            (300, 300, 600, 350),
        ]

        for (i, total) in totalsByIndex.enumerated() {
            try database.execute(
                """
                INSERT INTO provider_ingest_events (
                    provider_code, source_mode, provider_session_row_id,
                    provider_event_fingerprint, raw_reference_kind,
                    raw_reference_event_name, raw_reference_offset,
                    observed_at, payload_json, acceptance_state, created_at
                ) VALUES ('gemini', 'otel-inprocess', ?, ?, 'gemini-otel',
                          'gemini_cli.api_response', NULL, ?, '{}', 'accepted', ?);
                """,
                bindings: [
                    .integer(sessionRowID),
                    .text("fp-\(i)"),
                    .text("2026-04-09T13:00:0\(i)Z"),
                    .text("2026-04-09T13:00:0\(i)Z"),
                ]
            )

            let ingestEventRowID = try database.fetchOne("SELECT last_insert_rowid();") { stmt in
                SQLiteDatabase.columnInt64(stmt, index: 0)
            } ?? 0

            try database.execute(
                """
                INSERT INTO usage_samples (
                    provider_ingest_event_id, provider_code, provider_session_row_id,
                    observed_at, total_input_tokens, total_output_tokens,
                    total_cached_input_tokens, normalized_total_tokens,
                    normalized_delta_tokens, current_input_tokens, current_output_tokens,
                    burst_intensity_band, created_at
                ) VALUES (?, 'gemini', ?, ?, ?, ?, 0, ?, ?, NULL, NULL, 1, ?);
                """,
                bindings: [
                    .integer(ingestEventRowID),
                    .integer(sessionRowID),
                    .text("2026-04-09T13:00:0\(i)Z"),
                    .integer(total.input),
                    .integer(total.output),
                    .integer(total.normalized),
                    .integer(total.delta),
                    .text("2026-04-09T13:00:0\(i)Z"),
                ]
            )
        }
        try database.execute("PRAGMA foreign_keys = ON;")

        let totals = try manager.latestGeminiSessionTotals(
            activeWithinHours: 24,
            asOf: ISO8601DateFormatter().date(from: "2026-04-09T13:00:30Z")!
        )

        #expect(totals["session-A"]?.normalizedTotalTokens == 600)
        #expect(totals["session-A"]?.totalInputTokens == 300)
        #expect(totals["session-A"]?.totalOutputTokens == 300)
    }

    @Test
    func geminiCumulativeTrackerAccumulatesAndPicksUpFromSeed() {
        let seed: [String: GeminiSessionRunningTotals] = [
            "session-A": GeminiSessionRunningTotals(
                totalInputTokens: 300,
                totalOutputTokens: 300,
                totalCachedInputTokens: 0,
                normalizedTotalTokens: 600
            )
        ]
        let tracker = GeminiCumulativeTracker(seed: seed)

        // Existing session continues from the seed.
        let existingNext = tracker.recordEvent(
            sessionID: "session-A",
            inputTokens: 50,
            outputTokens: 25,
            cachedContentTokens: 0,
            totalTokens: 75
        )
        #expect(existingNext.totalInputTokens == 350)
        #expect(existingNext.totalOutputTokens == 325)
        #expect(existingNext.normalizedTotalTokens == 675)

        // Brand-new session starts from zero.
        let freshFirst = tracker.recordEvent(
            sessionID: "session-B",
            inputTokens: 10,
            outputTokens: 5,
            cachedContentTokens: 0,
            totalTokens: 15
        )
        #expect(freshFirst.totalInputTokens == 10)
        #expect(freshFirst.totalOutputTokens == 5)
        #expect(freshFirst.normalizedTotalTokens == 15)

        // Subsequent event on the new session continues monotonically.
        let freshSecond = tracker.recordEvent(
            sessionID: "session-B",
            inputTokens: 4,
            outputTokens: 6,
            cachedContentTokens: 0,
            totalTokens: 10
        )
        #expect(freshSecond.totalInputTokens == 14)
        #expect(freshSecond.totalOutputTokens == 11)
        #expect(freshSecond.normalizedTotalTokens == 25)
    }

    @Test
    func geminiOtelLogsServiceExtractsApiResponseEventsAndWritesInbox() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-gemini-logs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let inboxPath = tempDirectory.appendingPathComponent("gemini.ndjson").path
        let writer = GeminiOtelInboxWriter(inboxPath: inboxPath)
        let tracker = GeminiCumulativeTracker(seed: [:])
        let service = GeminiOtelLogsService(writer: writer, tracker: tracker)

        var logRecord = Opentelemetry_Proto_Logs_V1_LogRecord()
        logRecord.timeUnixNano = 1_775_000_000_000_000_000
        logRecord.attributes = [
            Self.makeStringAttr(key: "event.name", value: "gemini_cli.api_response"),
            Self.makeStringAttr(key: "session.id", value: "session-fixture"),
            Self.makeStringAttr(key: "model", value: "gemini-2.5-pro"),
            Self.makeIntAttr(key: "input_token_count", value: 1234),
            Self.makeIntAttr(key: "output_token_count", value: 567),
            Self.makeIntAttr(key: "cached_content_token_count", value: 0),
            Self.makeIntAttr(key: "thoughts_token_count", value: 0),
            Self.makeIntAttr(key: "tool_token_count", value: 0),
            Self.makeIntAttr(key: "total_token_count", value: 1801),
            Self.makeIntAttr(key: "duration_ms", value: 842),
        ]

        var scopeLogs = Opentelemetry_Proto_Logs_V1_ScopeLogs()
        scopeLogs.logRecords = [logRecord]

        var resourceLogs = Opentelemetry_Proto_Logs_V1_ResourceLogs()
        resourceLogs.scopeLogs = [scopeLogs]

        var request = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest()
        request.resourceLogs = [resourceLogs]

        try service.handleExportRequestForTesting(request)

        let contents = try String(contentsOfFile: inboxPath, encoding: .utf8)
        let line = contents.split(separator: "\n").first.map(String.init) ?? ""
        let decoded = try JSONDecoder().decode(ProviderUsageSampleEvent.self, from: Data(line.utf8))

        #expect(decoded.providerSessionID == "session-fixture")
        #expect(decoded.totalInputTokens == 1234)
        #expect(decoded.totalOutputTokens == 567)
        #expect(decoded.normalizedTotalTokens == 1801)
        #expect(decoded.modelSlug == "gemini-2.5-pro")
    }

    private static func makeStringAttr(
        key: String,
        value: String
    ) -> Opentelemetry_Proto_Common_V1_KeyValue {
        var attr = Opentelemetry_Proto_Common_V1_KeyValue()
        attr.key = key
        var anyValue = Opentelemetry_Proto_Common_V1_AnyValue()
        anyValue.value = .stringValue(value)
        attr.value = anyValue
        return attr
    }

    private static func makeIntAttr(
        key: String,
        value: Int64
    ) -> Opentelemetry_Proto_Common_V1_KeyValue {
        var attr = Opentelemetry_Proto_Common_V1_KeyValue()
        attr.key = key
        var anyValue = Opentelemetry_Proto_Common_V1_AnyValue()
        anyValue.value = .intValue(value)
        attr.value = anyValue
        return attr
    }

    @MainActor
    @Test
    func geminiReceiverSupervisorRunsAndStopsCleanly() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-gemini-supervisor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let inboxPath = tempDirectory.appendingPathComponent("gemini.ndjson").path
        let dataSource = StubGeminiReceiverDataSource()
        let supervisor = GeminiOtelReceiverSupervisor(
            dataSource: dataSource,
            inboxPath: inboxPath
        )

        await supervisor.start()
        if case .failed(let message) = supervisor.state {
            Issue.record("Supervisor failed to start: \(message)")
        }
        if case .running = supervisor.state {
            // ok
        } else {
            Issue.record("Expected supervisor.state == .running, got \(supervisor.state)")
        }

        await supervisor.stop()
        #expect(supervisor.state == .stopped)
    }

    @Test
    func geminiSettingsMergerInsertsTelemetryWhenAbsent() throws {
        let original = """
        {
          "theme": "Xcode",
          "selectedAuthType": "oauth-personal"
        }
        """

        let result = try GeminiSettingsMerger.merge(
            existingJSON: original,
            tokenmonHost: "127.0.0.1",
            tokenmonPort: 4317,
            allowOverride: false
        )

        switch result {
        case .merged(let updatedJSON):
            #expect(updatedJSON.contains("\"telemetry\""))
            #expect(updatedJSON.contains("\"http:\\/\\/127.0.0.1:4317\""))
            #expect(updatedJSON.contains("\"theme\""))
        case .conflict, .alreadyConfigured:
            Issue.record("Expected merged result, got \(result)")
        }
    }

    @Test
    func geminiSettingsMergerReportsConflictWhenExistingEndpointDiffers() throws {
        let original = """
        {
          "telemetry": {
            "enabled": true,
            "target": "gcp",
            "otlpEndpoint": "honeycomb.io:4317"
          }
        }
        """

        let result = try GeminiSettingsMerger.merge(
            existingJSON: original,
            tokenmonHost: "127.0.0.1",
            tokenmonPort: 4317,
            allowOverride: false
        )

        switch result {
        case .conflict(let existingEndpoint):
            #expect(existingEndpoint == "honeycomb.io:4317")
        case .merged, .alreadyConfigured:
            Issue.record("Expected conflict, got \(result)")
        }
    }

    @Test
    func geminiSettingsMergerOverridesWhenAllowed() throws {
        let original = """
        {
          "telemetry": {
            "enabled": true,
            "target": "gcp",
            "otlpEndpoint": "honeycomb.io:4317"
          }
        }
        """

        let result = try GeminiSettingsMerger.merge(
            existingJSON: original,
            tokenmonHost: "127.0.0.1",
            tokenmonPort: 4317,
            allowOverride: true
        )

        switch result {
        case .merged(let updatedJSON):
            #expect(updatedJSON.contains("\"http:\\/\\/127.0.0.1:4317\""))
            #expect(updatedJSON.contains("\"honeycomb.io:4317\"") == false)
        case .conflict, .alreadyConfigured:
            Issue.record("Expected merged result with allowOverride, got \(result)")
        }
    }

    @Test
    func geminiSettingsMergerNoOpsWhenAlreadyPointingAtTokenmon() throws {
        let original = """
        {
          "telemetry": {
            "enabled": true,
            "target": "local",
            "otlpEndpoint": "http://127.0.0.1:4317"
          }
        }
        """

        let result = try GeminiSettingsMerger.merge(
            existingJSON: original,
            tokenmonHost: "127.0.0.1",
            tokenmonPort: 4317,
            allowOverride: false
        )

        switch result {
        case .alreadyConfigured:
            break
        case .merged, .conflict:
            Issue.record("Expected alreadyConfigured, got \(result)")
        }
    }

    @Test
    func speciesDefinitionIncludesStatBlock() {
        let definition = SpeciesDefinition(
            id: "TEST_001",
            name: "TestMon",
            field: .grassland,
            rarity: .common,
            assetKey: "test_001",
            sortOrder: 999,
            stats: SpeciesStatBlock(
                planning: 3, design: 2, frontend: 1,
                backend: 5, pm: 2, infra: 1,
                traits: ["Deep Focus"]
            )
        )

        #expect(definition.stats.total == 14)
        #expect(definition.stats.backend == 5)
        #expect(definition.stats.traits == ["Deep Focus"])
        #expect(definition.stats.value(for: .backend) == 5)
    }

    @Test
    func allSpeciesStatsRespectRarityTotalConstraints() {
        let rarityRanges: [RarityTier: ClosedRange<Int>] = [
            .common: 12...18,
            .uncommon: 20...26,
            .rare: 28...34,
            .epic: 36...42,
            .legendary: 44...52,
        ]

        for species in SpeciesCatalog.all {
            let total = species.stats.total
            guard let range = rarityRanges[species.rarity] else {
                Issue.record("Unknown rarity for \(species.id)")
                continue
            }
            #expect(
                range.contains(total),
                "\(species.id) (\(species.rarity)) total \(total) outside range \(range)"
            )

            for axis in SpeciesStatAxis.allCases {
                let value = species.stats.value(for: axis)
                #expect(
                    (1...10).contains(value),
                    "\(species.id) \(axis.rawValue) = \(value) out of 1...10"
                )
            }

            let expectedTagCounts: [RarityTier: Int] = [
                .common: 1, .uncommon: 2, .rare: 3, .epic: 4, .legendary: 5,
            ]
            if let expectedCount = expectedTagCounts[species.rarity] {
                #expect(
                    species.stats.traits.count == expectedCount,
                    "\(species.id) (\(species.rarity)) has \(species.stats.traits.count) traits, expected \(expectedCount)"
                )
            }
        }
    }

    @Test
    func migrationAddsStatColumnsToSpeciesTable() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-stat-mig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()

        let row = try database.fetchOne(
            """
            SELECT stat_planning, stat_design, stat_frontend,
                   stat_backend, stat_pm, stat_infra, traits_json
            FROM species LIMIT 1;
            """
        ) { statement in
            (
                SQLiteDatabase.columnInt64(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1),
                SQLiteDatabase.columnInt64(statement, index: 2),
                SQLiteDatabase.columnInt64(statement, index: 3),
                SQLiteDatabase.columnInt64(statement, index: 4),
                SQLiteDatabase.columnInt64(statement, index: 5),
                SQLiteDatabase.columnText(statement, index: 6)
            )
        }

        #expect(row != nil)
    }

    @Test
    func partyMembersTableExistsAfterBootstrap() throws {
        let manager = try makeManager(prefix: "party-migration")
        let database = try manager.open()
        let columnSet = Set(try database.fetchAll(
            "PRAGMA table_info(party_members);"
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 1)
        })

        #expect(columnSet == ["species_id", "slot_order", "added_at"])
    }

    @Test
    func addToPartySucceedsForCapturedSpecies() throws {
        let manager = try makeManager(prefix: "party-add")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .grassland,
                rarity: .common,
                speciesID: "GRS_001",
                outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )

        try manager.addToParty(speciesID: "GRS_001")

        let summaries = try manager.partyMemberSummaries()
        #expect(summaries.count == 1)
        #expect(summaries[0].speciesID == "GRS_001")
        #expect(summaries[0].slotOrder == 1)
    }

    @Test
    func addToPartyThrowsWhenSpeciesNotCaptured() throws {
        let manager = try makeManager(prefix: "party-not-captured")

        #expect(throws: PartyStoreError.partyNotCapturedYet(speciesID: "GRS_001")) {
            try manager.addToParty(speciesID: "GRS_001")
        }
        #expect(try manager.partyMemberSummaries().count == 0)
    }

    @Test
    func addToPartyThrowsWhenFull() throws {
        let manager = try makeManager(prefix: "party-full")
        // GRS_001–GRS_010 are grassland/.common; GRS_011 is grassland/.uncommon
        let commonIDs = (1...10).map { String(format: "GRS_%03d", $0) }
        let eleventhID = "GRS_011"
        var occurredSeconds = 0
        for id in commonIDs {
            let occurredAt = String(format: "2026-04-14T00:00:%02dZ", occurredSeconds)
            occurredSeconds += 1
            _ = try manager.forgeEncounter(
                TokenmonDeveloperEncounterForgeRequest(
                    provider: .codex,
                    field: .grassland,
                    rarity: .common,
                    speciesID: id,
                    outcome: .captured,
                    occurredAt: occurredAt
                )
            )
        }
        let occurredAt11 = String(format: "2026-04-14T00:00:%02dZ", occurredSeconds)
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .grassland,
                rarity: .uncommon,
                speciesID: eleventhID,
                outcome: .captured,
                occurredAt: occurredAt11
            )
        )
        for id in commonIDs {
            try manager.addToParty(speciesID: id)
        }
        #expect(try manager.partyMemberSummaries().count == 10)

        #expect(throws: PartyStoreError.partyFull) {
            try manager.addToParty(speciesID: eleventhID)
        }
        #expect(try manager.partyMemberSummaries().count == 10)
    }

    @Test
    func addToPartyIsIdempotent() throws {
        let manager = try makeManager(prefix: "party-idempotent")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_001", outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")
        try manager.addToParty(speciesID: "GRS_001")

        let summaries = try manager.partyMemberSummaries()
        #expect(summaries.count == 1)
        #expect(summaries[0].slotOrder == 1)
    }

    @Test
    func removeFromPartyDeletesRow() throws {
        let manager = try makeManager(prefix: "party-remove")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_001", outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_002", outcome: .captured,
                occurredAt: "2026-04-14T00:00:01Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")
        try manager.addToParty(speciesID: "GRS_002")

        try manager.removeFromParty(speciesID: "GRS_001")

        let ids = try manager.partyMemberSummaries().map(\.speciesID)
        #expect(ids == ["GRS_002"])
    }

    @Test
    func removeFromPartyIsNoOpIfMissing() throws {
        let manager = try makeManager(prefix: "party-remove-noop")
        try manager.removeFromParty(speciesID: "GRS_001")  // must not throw
        #expect(try manager.partyMemberSummaries().count == 0)
    }

    @Test
    func reAddAfterRemoveAssignsNewSlot() throws {
        let manager = try makeManager(prefix: "party-readd")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_001", outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_002", outcome: .captured,
                occurredAt: "2026-04-14T00:00:01Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")  // slot 1
        try manager.addToParty(speciesID: "GRS_002")  // slot 2
        try manager.removeFromParty(speciesID: "GRS_001")
        try manager.addToParty(speciesID: "GRS_001")  // slot 3 (max+1)

        let summaries = try manager.partyMemberSummaries()
        let bySlot = Dictionary(uniqueKeysWithValues: summaries.map { ($0.speciesID, $0.slotOrder) })
        #expect(bySlot["GRS_002"] == 2)
        #expect(bySlot["GRS_001"] == 3)
    }

    @Test
    func partySpeciesIDSetAndFullness() throws {
        let manager = try makeManager(prefix: "party-set")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_001", outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )
        #expect(try manager.partySpeciesIDSet() == [])
        #expect(try manager.isPartyFull() == false)

        try manager.addToParty(speciesID: "GRS_001")
        #expect(try manager.partySpeciesIDSet() == ["GRS_001"])
        #expect(try manager.isPartyFull() == false)
    }

    @Test
    func ambientCompanionRosterReturnsByFieldWhenPartyEmpty() throws {
        let manager = try makeManager(prefix: "roster-byfield")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_001", outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )

        let roster = try manager.ambientCompanionRoster()
        switch roster {
        case .byField(let map):
            #expect(map.isEmpty == false)
        case .partyOverride:
            Issue.record("Expected byField when party empty")
        }
    }

    @Test
    func ambientCompanionRosterReturnsPartyOverrideWhenPartyNonEmpty() throws {
        let manager = try makeManager(prefix: "roster-party")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex, field: .grassland, rarity: .common,
                speciesID: "GRS_001", outcome: .captured,
                occurredAt: "2026-04-14T00:00:00Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")

        let roster = try manager.ambientCompanionRoster()
        switch roster {
        case .byField:
            Issue.record("Expected partyOverride when party non-empty")
        case .partyOverride(let assetKeys):
            #expect(assetKeys.count == 1)
        }
    }
}

private final class StubGeminiReceiverDataSource: GeminiOtelReceiverDataSource {
    func latestGeminiSessionTotals() throws -> [String: GeminiSessionRunningTotals] {
        [:]
    }
}
