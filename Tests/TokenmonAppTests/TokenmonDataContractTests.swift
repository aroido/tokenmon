import Foundation
import Testing
@testable import TokenmonGameEngine
@testable import TokenmonOtelProviders
@testable import TokenmonPersistence
import TokenmonDomain
@testable import TokenmonProviders

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
    func sqliteFetchOneMapsOnlyFirstRow() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-fetch-one-\(UUID().uuidString).sqlite")
            .path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let database = try SQLiteDatabase(path: dbPath)
        try database.execute("CREATE TABLE values_table(value INTEGER NOT NULL);")
        try database.execute("INSERT INTO values_table(value) VALUES (1), (2), (3);")

        var mappedRows = 0
        let value = try database.fetchOne(
            "SELECT value FROM values_table ORDER BY value ASC;"
        ) { statement in
            mappedRows += 1
            return SQLiteDatabase.columnInt64(statement, index: 0)
        }

        #expect(value == 1)
        #expect(mappedRows == 1)

        let readTransactionValue = try database.inReadTransaction {
            try database.fetchOne("SELECT COUNT(*) FROM values_table;") { statement in
                SQLiteDatabase.columnInt64(statement, index: 0)
            }
        }
        #expect(readTransactionValue == 3)
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
    func explorationAccumulatorUsesCollectionScaledThresholdRanges() {
        let config = ExplorationAccumulatorConfig()
        let earlyRange = config.scaledThresholdRange(capturedSpeciesCount: 0)
        let lateRange = config.scaledThresholdRange(capturedSpeciesCount: SpeciesCatalog.expectedCount)

        #expect(config.minimumEncounterThresholdTokens == 180_000)
        #expect(config.startingEncounterThresholdMaxTokens == 260_000)
        #expect(config.completionEncounterThresholdMinTokens == 700_000)
        #expect(config.maximumEncounterThresholdTokens == 900_000)
        #expect(earlyRange.min == 180_000)
        #expect(earlyRange.max == 260_000)
        #expect(lateRange.min == 700_000)
        #expect(lateRange.max == 900_000)
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
    func thresholdPolicyRefreshRebasesLegacyHighPendingThreshold() throws {
        let manager = try makeManager(prefix: "tokenmon-threshold-policy-rebase")
        let database = try manager.open()

        try manager.applyExplorationOverride(
            totalNormalizedTokens: 2_000_000,
            tokensSinceLastEncounter: 2_000_000,
            nextEncounterThresholdTokens: 6_000_000
        )
        try upsertStringSetting(
            database: database,
            key: "encounter_threshold_policy_version",
            value: "legacy-high-threshold"
        )

        try manager.refreshPendingEncounterThresholdPolicy()
        let summary = try manager.summary()
        let expectedThreshold = ExplorationAccumulatorConfig().tokensRequiredForEncounter(1)

        #expect(summary.totalNormalizedTokens == 2_000_000)
        #expect(summary.tokensSinceLastEncounter == expectedThreshold / 2)
        #expect(summary.nextEncounterThresholdTokens == expectedThreshold)
        #expect(summary.tokensUntilNextEncounter == expectedThreshold - (expectedThreshold / 2))
        #expect(summary.totalEncounters == 0)
    }

    @Test
    func thresholdPolicyRefreshUsesCurrentRangeWhenProgressIsBelowNewThreshold() throws {
        let manager = try makeManager(prefix: "tokenmon-threshold-policy-current-range")
        let database = try manager.open()

        try manager.applyExplorationOverride(
            totalNormalizedTokens: 50_000,
            tokensSinceLastEncounter: 50_000,
            nextEncounterThresholdTokens: 6_000_000
        )
        try upsertStringSetting(
            database: database,
            key: "encounter_threshold_policy_version",
            value: "legacy-high-threshold"
        )

        try manager.refreshPendingEncounterThresholdPolicy()
        let summary = try manager.summary()
        let range = ExplorationAccumulatorConfig().scaledThresholdRange(capturedSpeciesCount: 0)

        #expect(summary.tokensSinceLastEncounter == 50_000)
        #expect(summary.nextEncounterThresholdTokens >= range.min)
        #expect(summary.nextEncounterThresholdTokens <= range.max)
        #expect(summary.tokensUntilNextEncounter == summary.nextEncounterThresholdTokens - 50_000)
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

    @Test
    func gameplayBalanceKeepsRawTokensSeparateFromProgressTokens() throws {
        let manager = try makeManager(prefix: "tokenmon-gameplay-balance-raw")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-21T00:00:00Z"
        )
        try upsertStringSetting(
            database: database,
            key: "gameplay_balance_seed",
            value: "balance-test-seed"
        )

        let event = codexUsageEvent(
            sessionID: "balanced-codex-session",
            observedAt: "2026-04-21T00:01:00Z",
            totalInputTokens: 100_000,
            totalOutputTokens: 20_000,
            fingerprint: "codex:balanced-codex-session:001"
        )
        let result = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            [event],
            sourceKey: "balanced-codex",
            sourceKind: "ndjson_file"
        )
        #expect(result.acceptedEvents == 1)

        let row = try database.fetchOne(
            """
            SELECT normalized_delta_tokens,
                   gameplay_delta_tokens,
                   gameplay_balance_bucket,
                   gameplay_balance_weight,
                   gameplay_balance_policy
            FROM usage_samples
            WHERE provider_code = 'codex'
            LIMIT 1;
            """
        ) { statement in
            (
                rawDelta: SQLiteDatabase.columnInt64(statement, index: 0),
                gameplayDelta: SQLiteDatabase.columnInt64(statement, index: 1),
                bucket: SQLiteDatabase.columnOptionalText(statement, index: 2),
                weight: SQLiteDatabase.columnOptionalDouble(statement, index: 3),
                policy: SQLiteDatabase.columnOptionalText(statement, index: 4)
            )
        }

        #expect(row?.rawDelta == 120_000)
        #expect((row?.gameplayDelta ?? 0) > 0)
        #expect((row?.gameplayDelta ?? 0) < 30_000)
        #expect(row?.bucket == "codex:gpt-5-4")
        #expect((row?.weight ?? 0) > 0)
        #expect(row?.policy?.contains("cold_start_provider_fallback") == true)

        let ingestPayloadTotal = try database.fetchOne(
            """
            SELECT json_extract(payload_json, '$.normalized_total_tokens')
            FROM provider_ingest_events
            WHERE provider_code = 'codex'
            LIMIT 1;
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }
        #expect(ingestPayloadTotal == 120_000)

        let explorationTokens = try database.fetchOne(
            "SELECT total_normalized_tokens FROM exploration_state WHERE exploration_state_id = 1;"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }
        #expect(explorationTokens == row?.gameplayDelta)
    }

    @Test
    func gameplayBalanceStronglyCapsLargeCodexColdStartDeltas() throws {
        let manager = try makeManager(prefix: "tokenmon-gameplay-balance-large-codex")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-21T00:00:00Z"
        )
        try upsertStringSetting(
            database: database,
            key: "gameplay_balance_seed",
            value: "balance-test-seed"
        )

        let event = codexUsageEvent(
            sessionID: "large-codex-session",
            observedAt: "2026-04-21T00:01:00Z",
            totalInputTokens: 400_000,
            totalOutputTokens: 80_000,
            fingerprint: "codex:large-codex-session:001"
        )
        let result = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            [event],
            sourceKey: "large-codex",
            sourceKind: "ndjson_file"
        )
        #expect(result.acceptedEvents == 1)

        let row = try database.fetchOne(
            """
            SELECT normalized_delta_tokens,
                   gameplay_delta_tokens,
                   gameplay_balance_policy
            FROM usage_samples
            WHERE provider_code = 'codex'
            LIMIT 1;
            """
        ) { statement in
            (
                rawDelta: SQLiteDatabase.columnInt64(statement, index: 0),
                gameplayDelta: SQLiteDatabase.columnInt64(statement, index: 1),
                policy: SQLiteDatabase.columnText(statement, index: 2)
            )
        }

        #expect(row?.rawDelta == 480_000)
        #expect((row?.gameplayDelta ?? 0) > 0)
        #expect((row?.gameplayDelta ?? Int64.max) < 80_000)
        #expect(row?.policy.contains("soft_cap") == true)
    }

    @Test
    func gameplayBalanceResetsLearnedBucketsWhenPolicyChanges() throws {
        let manager = try makeManager(prefix: "tokenmon-gameplay-balance-policy-reset")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-21T00:00:00Z"
        )
        try upsertStringSetting(
            database: database,
            key: "gameplay_balance_seed",
            value: "balance-test-seed"
        )
        try upsertStringSetting(
            database: database,
            key: "gameplay_balance_policy_version",
            value: "gameplay_balance_v1"
        )
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
            ) VALUES (
                'codex:gpt-5-4',
                'codex',
                'gpt-5-4',
                0.65,
                5000000,
                99,
                99,
                '2026-04-21T00:00:00Z',
                '2026-04-21T00:00:00Z'
            );
            """
        )

        let event = codexUsageEvent(
            sessionID: "policy-reset-codex-session",
            observedAt: "2026-04-21T00:01:00Z",
            totalInputTokens: 400_000,
            totalOutputTokens: 80_000,
            fingerprint: "codex:policy-reset-codex-session:001"
        )
        let result = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            [event],
            sourceKey: "policy-reset-codex",
            sourceKind: "ndjson_file"
        )
        #expect(result.acceptedEvents == 1)

        let usageRow = try database.fetchOne(
            """
            SELECT gameplay_delta_tokens,
                   gameplay_balance_weight,
                   gameplay_balance_policy
            FROM usage_samples
            WHERE provider_code = 'codex'
            LIMIT 1;
            """
        ) { statement in
            (
                gameplayDelta: SQLiteDatabase.columnInt64(statement, index: 0),
                weight: SQLiteDatabase.columnDouble(statement, index: 1),
                policy: SQLiteDatabase.columnText(statement, index: 2)
            )
        }
        #expect((usageRow?.gameplayDelta ?? Int64.max) < 80_000)
        #expect((usageRow?.weight ?? 1) < 0.20)
        #expect(usageRow?.policy.contains("gameplay_balance_v2") == true)

        let bucket = try database.fetchOne(
            """
            SELECT effective_weight,
                   sample_count
            FROM gameplay_balance_buckets
            WHERE bucket_key = 'codex:gpt-5-4'
            LIMIT 1;
            """
        ) { statement in
            (
                effectiveWeight: SQLiteDatabase.columnDouble(statement, index: 0),
                sampleCount: SQLiteDatabase.columnInt64(statement, index: 1)
            )
        }
        #expect((bucket?.effectiveWeight ?? 1) < 0.20)
        #expect(bucket?.sampleCount == 1)
    }

    @Test
    func gameplayBalanceLearnsHighRateBucketsWithoutRewritingAccounting() throws {
        let manager = try makeManager(prefix: "tokenmon-gameplay-balance-dynamic")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-21T00:00:00Z"
        )
        try upsertStringSetting(
            database: database,
            key: "gameplay_balance_seed",
            value: "balance-test-seed"
        )

        let events = (1...9).map { index in
            let index64 = Int64(index)
            return codexUsageEvent(
                sessionID: "dynamic-codex-session",
                observedAt: String(format: "2026-04-21T00:%02d:00Z", index * 2),
                totalInputTokens: index64 * 80_000,
                totalOutputTokens: index64 * 20_000,
                fingerprint: "codex:dynamic-codex-session:\(index)"
            )
        }
        let result = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            events,
            sourceKey: "dynamic-codex",
            sourceKind: "ndjson_file"
        )
        #expect(result.acceptedEvents == 9)

        let balanceRows = try database.fetchAll(
            """
            SELECT normalized_delta_tokens,
                   gameplay_delta_tokens,
                   gameplay_balance_weight,
                   gameplay_balance_policy
            FROM usage_samples
            WHERE provider_code = 'codex'
            ORDER BY usage_sample_id;
            """
        ) { statement in
            (
                rawDelta: SQLiteDatabase.columnInt64(statement, index: 0),
                gameplayDelta: SQLiteDatabase.columnInt64(statement, index: 1),
                weight: SQLiteDatabase.columnDouble(statement, index: 2),
                policy: SQLiteDatabase.columnText(statement, index: 3)
            )
        }

        #expect(balanceRows.count == 9)
        #expect(balanceRows.allSatisfy { $0.rawDelta == 100_000 })
        #expect(balanceRows.first?.policy.contains("cold_start_provider_fallback") == true)
        #expect(balanceRows.last?.policy.contains("dynamic_alpha_0_85") == true)
        #expect((balanceRows.last?.weight ?? 1) < (balanceRows.first?.weight ?? 0))
        #expect(balanceRows.allSatisfy { $0.gameplayDelta > 0 && $0.gameplayDelta < $0.rawDelta })

        let rawSum = balanceRows.reduce(Int64(0)) { $0 + $1.rawDelta }
        let gameplaySum = balanceRows.reduce(Int64(0)) { $0 + $1.gameplayDelta }
        #expect(rawSum == 900_000)
        #expect(gameplaySum < rawSum)

        let bucket = try database.fetchOne(
            """
            SELECT bucket_key,
                   sample_count,
                   active_minutes,
                   observed_rate_tokens_per_minute
            FROM gameplay_balance_buckets
            WHERE bucket_key = 'codex:gpt-5-4'
            LIMIT 1;
            """
        ) { statement in
            (
                bucketKey: SQLiteDatabase.columnText(statement, index: 0),
                sampleCount: SQLiteDatabase.columnInt64(statement, index: 1),
                activeMinutes: SQLiteDatabase.columnDouble(statement, index: 2),
                observedRate: SQLiteDatabase.columnDouble(statement, index: 3)
            )
        }
        #expect(bucket?.bucketKey == "codex:gpt-5-4")
        #expect(bucket?.sampleCount == 9)
        #expect((bucket?.activeMinutes ?? 0) >= 0.25)
        #expect((bucket?.observedRate ?? 0) > 0)
    }

    @Test
    func recoveryUsageDoesNotTrainGameplayBalance() throws {
        let manager = try makeManager(prefix: "tokenmon-gameplay-balance-recovery")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "gameplay_balance_seed",
            value: "balance-test-seed"
        )

        let event = codexUsageEvent(
            sessionID: "recovery-codex-session",
            observedAt: "2026-04-21T00:01:00Z",
            totalInputTokens: 100_000,
            totalOutputTokens: 20_000,
            fingerprint: "codex:recovery-codex-session:001"
        )
        let result = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            [event],
            sourceKey: "recovery-codex",
            sourceKind: "recovery_scan"
        )
        #expect(result.acceptedEvents == 1)

        let row = try database.fetchOne(
            """
            SELECT gameplay_delta_tokens,
                   gameplay_balance_bucket,
                   gameplay_balance_weight,
                   gameplay_balance_policy
            FROM usage_samples
            WHERE provider_code = 'codex'
            LIMIT 1;
            """
        ) { statement in
            (
                gameplayDelta: SQLiteDatabase.columnInt64(statement, index: 0),
                bucket: SQLiteDatabase.columnOptionalText(statement, index: 1),
                weight: SQLiteDatabase.columnOptionalDouble(statement, index: 2),
                policy: SQLiteDatabase.columnOptionalText(statement, index: 3)
            )
        }
        #expect(row?.gameplayDelta == 0)
        #expect(row?.bucket == nil)
        #expect(row?.weight == nil)
        #expect(row?.policy == nil)
        #expect(try rowCount(in: "gameplay_balance_buckets", database: database) == 0)
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

    private func upsertStringSetting(
        database: SQLiteDatabase,
        key: String,
        value: String
    ) throws {
        try database.execute(
            """
            INSERT INTO settings (
                setting_key,
                setting_value_json,
                updated_at
            ) VALUES (?, ?, '2026-04-21T00:00:00Z')
            ON CONFLICT(setting_key) DO UPDATE SET
                setting_value_json = excluded.setting_value_json,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(key),
                .text("\"\(value)\""),
            ]
        )
    }

    private func codexUsageEvent(
        sessionID: String,
        observedAt: String,
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        fingerprint: String
    ) -> ProviderUsageSampleEvent {
        ProviderUsageSampleEvent(
            eventType: "provider_usage_sample",
            provider: .codex,
            sourceMode: "codex_exec_json",
            providerSessionID: sessionID,
            observedAt: observedAt,
            workspaceDir: "/tmp/tokenmon-fixture",
            modelSlug: "gpt-5.4",
            transcriptPath: nil,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: 1_000,
            normalizedTotalTokens: totalInputTokens + totalOutputTokens,
            providerEventFingerprint: fingerprint,
            rawReference: ProviderRawReference(
                kind: "jsonl",
                offset: nil,
                eventName: "turn.completed"
            ),
            currentInputTokens: totalInputTokens,
            currentOutputTokens: totalOutputTokens,
            sessionOriginHint: .startedDuringLiveRuntime
        )
    }

    private func rowCount(in table: String, database: SQLiteDatabase) throws -> Int64 {
        try database.fetchOne("SELECT COUNT(*) FROM \(table);") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
    }

    private func jsonObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
    func providerCodeIncludesCursorWithExpectedMetadata() {
        #expect(ProviderCode.allCases.contains(.cursor))
        #expect(ProviderCode(rawValue: "cursor") == .cursor)
        #expect(ProviderCode.cursor.displayName == "Cursor")
        #expect(ProviderCode.cursor.defaultSupportLevel == "managed_only")
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

        #expect(version >= 7)
        #expect(usageSampleCount == 1)
        #expect(encounterCount == 1)
        #expect(gameplayColumns.contains("gameplay_eligibility"))
        #expect(gameplayColumns.contains("gameplay_delta_tokens"))
    }

    @Test
    func migrationVersionTenRepairsLegacyCodexCachedInputDoubleCounting() throws {
        let manager = try makeManager(prefix: "tokenmon-mig-v10-codex-accounting")
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
                ) VALUES (
                    100,
                    'codex',
                    'legacy-codex-session',
                    'authoritative',
                    'codex_session_store_live',
                    'gpt-5.4',
                    NULL,
                    '/tmp/legacy-codex.jsonl',
                    '2026-04-10T10:00:00Z',
                    NULL,
                    '2026-04-10T10:02:00Z',
                    'active',
                    '2026-04-10T10:00:00Z',
                    '2026-04-10T10:02:00Z'
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
                ) VALUES
                    (
                        1000,
                        'codex',
                        'codex_session_store_live',
                        100,
                        NULL,
                        'legacy-codex-1',
                        'session_store_live',
                        'token_count',
                        '1',
                        '2026-04-10T10:01:00Z',
                        '{"event_type":"provider_usage_sample","provider":"codex","source_mode":"codex_session_store_live","provider_session_id":"legacy-codex-session","observed_at":"2026-04-10T10:01:00Z","total_input_tokens":1000,"total_output_tokens":400,"total_cached_input_tokens":100,"normalized_total_tokens":1500,"provider_event_fingerprint":"legacy-codex-1","raw_reference":{"kind":"session_store_live","event_name":"token_count"}}',
                        'accepted',
                        NULL,
                        '2026-04-10T10:01:00Z'
                    ),
                    (
                        1001,
                        'codex',
                        'codex_session_store_live',
                        100,
                        NULL,
                        'legacy-codex-2',
                        'session_store_live',
                        'token_count',
                        '2',
                        '2026-04-10T10:02:00Z',
                        '{"event_type":"provider_usage_sample","provider":"codex","source_mode":"codex_session_store_live","provider_session_id":"legacy-codex-session","observed_at":"2026-04-10T10:02:00Z","total_input_tokens":2000,"total_output_tokens":800,"total_cached_input_tokens":200,"normalized_total_tokens":3000,"provider_event_fingerprint":"legacy-codex-2","raw_reference":{"kind":"session_store_live","event_name":"token_count"}}',
                        'accepted',
                        NULL,
                        '2026-04-10T10:02:00Z'
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
                    gameplay_eligibility,
                    gameplay_delta_tokens,
                    burst_intensity_band,
                    created_at
                ) VALUES
                    (10000, 1000, 'codex', 100, '2026-04-10T10:01:00Z', 1000, 400, 100, 1500, 1500, 1000, 400, 'recovery_only', 0, 1, '2026-04-10T10:01:00Z'),
                    (10001, 1001, 'codex', 100, '2026-04-10T10:02:00Z', 2000, 800, 200, 3000, 1500, 1000, 400, 'eligible_live', 1500, 1, '2026-04-10T10:02:00Z');
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
                    (
                        'usage_sample_recorded:10000',
                        'usage_sample_recorded',
                        '2026-04-10T10:01:00Z',
                        'tests',
                        'legacy-codex-1',
                        NULL,
                        'provider_session',
                        'codex:legacy-codex-session',
                        '{"usage_sample_id":10000,"provider":"codex","provider_session_id":"legacy-codex-session","normalized_total_tokens":1500,"normalized_delta_tokens":1500,"gameplay_delta_tokens":0}',
                        '2026-04-10T10:01:00Z'
                    ),
                    (
                        'usage_sample_recorded:10001',
                        'usage_sample_recorded',
                        '2026-04-10T10:02:00Z',
                        'tests',
                        'legacy-codex-2',
                        NULL,
                        'provider_session',
                        'codex:legacy-codex-session',
                        '{"usage_sample_id":10001,"provider":"codex","provider_session_id":"legacy-codex-session","normalized_total_tokens":3000,"normalized_delta_tokens":1500,"gameplay_delta_tokens":1500}',
                        '2026-04-10T10:02:00Z'
                    );
                """
            )
            try database.execute("PRAGMA user_version = 9;")
        }

        let repairedDatabase = try manager.open()

        let repairedRows: [(Int64, Int64, Int64, Int64)] = try repairedDatabase.fetchAll(
            """
            SELECT usage_sample_id,
                   normalized_total_tokens,
                   normalized_delta_tokens,
                   gameplay_delta_tokens
            FROM usage_samples
            WHERE usage_sample_id IN (10000, 10001)
            ORDER BY usage_sample_id;
            """
        ) { statement in
            (
                SQLiteDatabase.columnInt64(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1),
                SQLiteDatabase.columnInt64(statement, index: 2),
                SQLiteDatabase.columnInt64(statement, index: 3)
            )
        }
        #expect(repairedRows.map { $0.1 } == [1_400, 2_800])
        #expect(repairedRows.map { $0.2 } == [1_400, 1_400])
        #expect(repairedRows.map { $0.3 } == [0, 1_400])

        let repairedIngestTotals: [Int64] = try repairedDatabase.fetchAll(
            """
            SELECT json_extract(payload_json, '$.normalized_total_tokens')
            FROM provider_ingest_events
            WHERE provider_ingest_event_id IN (1000, 1001)
            ORDER BY provider_ingest_event_id;
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }
        #expect(repairedIngestTotals == [1_400, 2_800])

        let repairedEventPayloads: [(Int64, Int64, Int64)] = try repairedDatabase.fetchAll(
            """
            SELECT json_extract(payload_json, '$.normalized_total_tokens'),
                   json_extract(payload_json, '$.normalized_delta_tokens'),
                   json_extract(payload_json, '$.gameplay_delta_tokens')
            FROM domain_events
            WHERE event_id IN ('usage_sample_recorded:10000', 'usage_sample_recorded:10001')
            ORDER BY event_id;
            """
        ) { statement in
            (
                SQLiteDatabase.columnInt64(statement, index: 0),
                SQLiteDatabase.columnInt64(statement, index: 1),
                SQLiteDatabase.columnInt64(statement, index: 2)
            )
        }
        #expect(repairedEventPayloads.map { $0.0 } == [1_400, 2_800])
        #expect(repairedEventPayloads.map { $0.1 } == [1_400, 1_400])
        #expect(repairedEventPayloads.map { $0.2 } == [0, 1_400])

        let version = try repairedDatabase.fetchOne("PRAGMA user_version;") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
        #expect(version >= 10)
    }

    @Test
    func migrationVersionFourteenCopiesLegacyCursorUsageToStatsOnlyRowsAndNeutralizesGameplay() throws {
        let manager = try makeManager(prefix: "tokenmon-mig-v14-cursor-legacy")
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
                ) VALUES (
                    200,
                    'cursor',
                    'legacy-cursor-session',
                    'inferred',
                    'cursor_legacy_local_usage',
                    'gpt-5.4',
                    NULL,
                    NULL,
                    '2026-04-18T01:00:00Z',
                    NULL,
                    '2026-04-18T01:05:00Z',
                    'active',
                    '2026-04-18T01:00:00Z',
                    '2026-04-18T01:05:00Z'
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
                ) VALUES
                    (2000, 'cursor', 'cursor_legacy_local_usage', 200, NULL, 'legacy-cursor-1', 'legacy_usage_sample', 'token_count', '1', '2026-04-18T01:00:00Z', '{"provider":"cursor","normalized_total_tokens":150}', 'accepted', NULL, '2026-04-18T01:00:00Z'),
                    (2001, 'cursor', 'cursor_legacy_local_usage', 200, NULL, 'legacy-cursor-2', 'legacy_usage_sample', 'token_count', '2', '2026-04-18T01:05:00Z', '{"provider":"cursor","normalized_total_tokens":245}', 'accepted', NULL, '2026-04-18T01:05:00Z');
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
                    gameplay_balance_bucket,
                    gameplay_balance_weight,
                    gameplay_balance_policy,
                    burst_intensity_band,
                    created_at
                ) VALUES
                    (20000, 2000, 'cursor', 200, '2026-04-18T01:00:00Z', 100, 40, 10, 150, 150, 100, 40, 'eligible_live', 150, 'cursor:gpt-5-4', 1.0, 'legacy', 1, '2026-04-18T01:00:00Z'),
                    (20001, 2001, 'cursor', 200, '2026-04-18T01:05:00Z', 180, 70, 15, 245, 95, 80, 30, 'eligible_live', 95, 'cursor:gpt-5-4', 1.0, 'legacy', 1, '2026-04-18T01:05:00Z');
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
                    'legacy-cursor-encounter',
                    1,
                    'cursor',
                    200,
                    20001,
                    1,
                    '2026-04-18T01:05:00Z',
                    'grassland',
                    'common',
                    'GRS_001',
                    1,
                    0.7,
                    0.1,
                    'captured',
                    '2026-04-18T01:05:00Z'
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
                ) VALUES (
                    'usage_sample_recorded:20001',
                    'usage_sample_recorded',
                    '2026-04-18T01:05:00Z',
                    'tests',
                    'legacy-cursor-2',
                    NULL,
                    'provider_session',
                    'cursor:legacy-cursor-session',
                    '{"usage_sample_id":20001,"provider":"cursor","gameplay_eligibility":"eligible_live","gameplay_delta_tokens":95}',
                    '2026-04-18T01:05:00Z'
                );
                """
            )
            try database.execute("PRAGMA user_version = 13;")
        }

        let repairedDatabase = try manager.open()

        let accountRows = try repairedDatabase.fetchAll(
            """
            SELECT provider_event_fingerprint,
                   usage_kind,
                   input_tokens,
                   output_tokens,
                   cached_input_tokens,
                   normalized_delta_tokens,
                   raw_reference_kind,
                   raw_reference_offset
            FROM account_usage_samples
            WHERE provider_code = 'cursor'
            ORDER BY account_usage_sample_id;
            """
        ) { statement in
            (
                fingerprint: SQLiteDatabase.columnText(statement, index: 0),
                usageKind: SQLiteDatabase.columnText(statement, index: 1),
                input: SQLiteDatabase.columnInt64(statement, index: 2),
                output: SQLiteDatabase.columnInt64(statement, index: 3),
                cached: SQLiteDatabase.columnInt64(statement, index: 4),
                normalized: SQLiteDatabase.columnInt64(statement, index: 5),
                rawKind: SQLiteDatabase.columnText(statement, index: 6),
                rawOffset: SQLiteDatabase.columnText(statement, index: 7)
            )
        }

        #expect(accountRows.map { $0.fingerprint } == [
            "cursor:legacy-usage-sample:20000",
            "cursor:legacy-usage-sample:20001",
        ])
        #expect(accountRows.map { $0.usageKind } == ["legacy_usage_sample", "legacy_usage_sample"])
        #expect(accountRows.map { $0.input } == [100, 80])
        #expect(accountRows.map { $0.output } == [40, 30])
        #expect(accountRows.map { $0.cached } == [10, 5])
        #expect(accountRows.map { $0.normalized } == [150, 95])
        #expect(accountRows.map { $0.rawKind } == ["legacy_usage_sample", "legacy_usage_sample"])
        #expect(accountRows.map { $0.rawOffset } == ["20000", "20001"])

        let usageRows = try repairedDatabase.fetchAll(
            """
            SELECT gameplay_eligibility,
                   gameplay_delta_tokens,
                   gameplay_balance_bucket,
                   gameplay_balance_weight,
                   gameplay_balance_policy
            FROM usage_samples
            WHERE provider_code = 'cursor'
            ORDER BY usage_sample_id;
            """
        ) { statement in
            (
                eligibility: SQLiteDatabase.columnText(statement, index: 0),
                gameplayDelta: SQLiteDatabase.columnInt64(statement, index: 1),
                bucket: SQLiteDatabase.columnOptionalText(statement, index: 2),
                weight: SQLiteDatabase.columnOptionalDouble(statement, index: 3),
                policy: SQLiteDatabase.columnOptionalText(statement, index: 4)
            )
        }
        #expect(usageRows.map { $0.eligibility } == ["recovery_only", "recovery_only"])
        #expect(usageRows.map { $0.gameplayDelta } == [0, 0])
        #expect(usageRows.allSatisfy { $0.bucket == nil && $0.weight == nil && $0.policy == nil })
        #expect(try rowCount(in: "encounters", database: repairedDatabase) == 1)

        let eventPayload = try #require(repairedDatabase.fetchOne(
            """
            SELECT payload_json
            FROM domain_events
            WHERE event_id = 'usage_sample_recorded:20001';
            """
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        })
        let payload = try jsonObject(eventPayload)
        #expect(payload["gameplay_eligibility"] as? String == "recovery_only")
        #expect(payload["gameplay_delta_tokens"] as? Int == 0)

        let cursor = try #require(
            try manager.providerHealthSummaries(database: repairedDatabase)
                .first(where: { $0.provider == .cursor })
        )
        #expect(cursor.reliabilityLabel == "stats_only")
        #expect(cursor.liveGameplayArmed == false)
        #expect(cursor.diagnosticFacts["account_usage_samples"] == "2")
        #expect(cursor.diagnosticFacts["legacy_usage_samples"] == "2")
        #expect(cursor.diagnosticFacts["legacy_gameplay_delta_tokens"] == "0")
        #expect(cursor.diagnosticFacts["legacy_cursor_encounters"] == "1")
        #expect(cursor.diagnosticFacts["legacy_cursor_gameplay_history_detected"] == "yes")
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
        #expect(codex.reliabilityLabel == "best_effort")
        #expect(codex.liveGameplayArmed)
        #expect(claude.offlineDashboardRecovery == "known_transcript_only")
        #expect(claude.liveGameplayArmed == false)
        #expect(gemini.offlineDashboardRecovery == "unavailable")
        #expect(gemini.reliabilityLabel == "first_class")
    }

    @Test
    func providerHealthSummariesLabelCodexExecJSONAsManagedFirstClass() throws {
        let manager = try makeManager(prefix: "tokenmon-codex-managed-health")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:00:00Z")
        let database = try manager.open()
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
                'codex_exec_json',
                'active',
                'Codex managed JSON ingest active',
                '2026-04-10T10:12:00Z',
                NULL,
                NULL,
                NULL,
                '2026-04-10T10:12:00Z'
            );
            """
        )

        let codex = try #require(try manager.providerHealthSummaries().first(where: { $0.provider == .codex }))
        #expect(codex.sourceMode == "codex_exec_json")
        #expect(codex.supportLevel == "best_effort")
        #expect(codex.reliabilityLabel == "managed_first_class")
        #expect(codex.liveGameplayArmed)
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
    func codexTranscriptBackfillUsesProviderTotalWithoutDoubleCountingCachedInput() throws {
        let result = try CodexTranscriptBackfillAdapter.importTranscript(
            from: "Fixtures/CodexTranscript/token-counts.jsonl"
        )

        #expect(result.events.count == 2)
        #expect(result.events.map(\.totalInputTokens) == [1_200, 2_400])
        #expect(result.events.map(\.totalOutputTokens) == [600, 1_200])
        #expect(result.events.map(\.totalCachedInputTokens) == [200, 300])
        #expect(result.events.map(\.normalizedTotalTokens) == [1_800, 3_600])
    }

    @Test
    func codexExecJSONUsesProviderTotalWithoutDoubleCountingCachedInput() throws {
        let adapter = CodexExecJSONAdapter()
        _ = try adapter.consumeLine(
            #"{"type":"thread.started","thread_id":"thread_exec_accounting"}"#,
            lineNumber: 1
        )

        let firstResult = try adapter.consumeLine(
            #"{"type":"turn.completed","thread_id":"thread_exec_accounting","turn_id":"turn_001","timestamp":"2026-04-04T00:12:00Z","usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":600,"total_tokens":1800}}"#,
            lineNumber: 2
        )
        let secondResult = try adapter.consumeLine(
            #"{"type":"turn.completed","thread_id":"thread_exec_accounting","turn_id":"turn_002","timestamp":"2026-04-04T00:13:00Z","usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":500}}"#,
            lineNumber: 3
        )

        guard case .usageSample(let first) = firstResult else {
            Issue.record("Expected first Codex turn to produce a usage sample")
            return
        }
        guard case .usageSample(let second) = secondResult else {
            Issue.record("Expected second Codex turn to produce a usage sample")
            return
        }

        #expect(first.totalInputTokens == 1_200)
        #expect(first.totalOutputTokens == 600)
        #expect(first.totalCachedInputTokens == 200)
        #expect(first.normalizedTotalTokens == 1_800)
        #expect(second.totalInputTokens == 2_200)
        #expect(second.totalOutputTokens == 1_100)
        #expect(second.totalCachedInputTokens == 300)
        #expect(second.normalizedTotalTokens == 3_300)
    }

    @Test
    func claudeStatusLineUsesCumulativeTotalsWithoutAddingCurrentCacheAgain() throws {
        let payload = """
        {
          "cwd": "/tmp/tokenmon-fixture",
          "session_id": "claude_statusline_cache_fixture",
          "transcript_path": "/tmp/claude-statusline-cache-fixture.jsonl",
          "model": { "id": "claude-opus-4-1", "display_name": "Opus" },
          "context_window": {
            "total_input_tokens": 1200,
            "total_output_tokens": 600,
            "current_usage": {
              "input_tokens": 100,
              "output_tokens": 50,
              "cache_creation_input_tokens": 700,
              "cache_read_input_tokens": 900
            }
          }
        }
        """

        let result = try ClaudeStatusLineAdapter.importPayload(json: payload)

        #expect(result.normalizedTotalTokens == 1_800)
    }

    @Test
    func claudeTranscriptBackfillCountsCacheFieldsWhenTranscriptUsageExposesThemSeparately() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-claude-transcript-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let transcriptPath = tempDirectory.appendingPathComponent("claude.jsonl")
        try (
            """
            {"session_id":"claude-cache-fixture","timestamp":"2026-04-18T01:00:00Z","message":{"id":"msg-1","role":"assistant","model":"claude-opus-4-1","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":7,"cache_read_input_tokens":3}}}
            """
            + "\n"
        ).write(to: transcriptPath, atomically: true, encoding: .utf8)

        let result = try ClaudeTranscriptBackfillAdapter.importTranscript(
            from: transcriptPath.path,
            config: ClaudeTranscriptBackfillAdapterConfig(sessionIDFallback: "claude-cache-fixture")
        )

        #expect(result.events.count == 1)
        #expect(result.events[0].totalInputTokens == 100)
        #expect(result.events[0].totalOutputTokens == 50)
        #expect(result.events[0].totalCachedInputTokens == 10)
        #expect(result.events[0].normalizedTotalTokens == 160)
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
    func latestClaudeSessionTotalsFiltersByIngestEventSourceMode() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-claude-totals-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let database = try manager.open()
        try database.execute("PRAGMA foreign_keys = OFF;")

        try insertClaudeSeedRow(
            database: database,
            sessionID: "session-A",
            sourceMode: "claude_otel_api_request_live",
            fingerprint: "fp-A",
            input: 1200, output: 600, cached: 100, normalized: 1800
        )
        try insertClaudeSeedRow(
            database: database,
            sessionID: "session-B",
            sourceMode: "claude_hook_enrichment",
            fingerprint: "fp-B",
            input: 900, output: 400, cached: 50, normalized: 1300
        )
        try database.execute("PRAGMA foreign_keys = ON;")

        let totals = try manager.latestClaudeSessionTotals(
            activeWithinHours: 24,
            asOf: ISO8601DateFormatter().date(from: "2026-04-09T13:00:30Z")!
        )

        #expect(totals["session-A"]?.normalizedTotalTokens == 1800)
        #expect(totals["session-A"]?.totalInputTokens == 1200)
        #expect(totals["session-A"]?.totalOutputTokens == 600)
        #expect(totals["session-B"] == nil)
    }

    @Test
    func latestClaudeSessionTotalsReturnsEmptyOnFreshDatabase() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-claude-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dbPath = tempDirectory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: dbPath)
        try manager.bootstrap()

        let totals = try manager.latestClaudeSessionTotals(
            activeWithinHours: 24,
            asOf: ISO8601DateFormatter().date(from: "2026-04-09T13:00:00Z")!
        )

        #expect(totals.isEmpty)
    }

    private func insertClaudeSeedRow(
        database: SQLiteDatabase,
        sessionID: String,
        sourceMode: String,
        fingerprint: String,
        input: Int64,
        output: Int64,
        cached: Int64,
        normalized: Int64,
        observedAt: String = "2026-04-09T13:00:00Z"
    ) throws {
        try database.execute(
            """
            INSERT INTO provider_sessions (
                provider_code, provider_session_id, session_identity_kind, source_mode,
                model_slug, workspace_dir, transcript_path, started_at, ended_at,
                last_seen_at, session_state, created_at, updated_at
            ) VALUES ('claude', ?, 'claude.session_id', ?, 'claude-sonnet-4-6',
                      NULL, NULL, '2026-04-09T10:00:00Z', NULL, ?, 'active', ?, ?);
            """,
            bindings: [
                .text(sessionID), .text(sourceMode),
                .text(observedAt), .text(observedAt), .text(observedAt),
            ]
        )
        let sessionRowID = try database.fetchOne("SELECT last_insert_rowid();") { stmt in
            SQLiteDatabase.columnInt64(stmt, index: 0)
        } ?? 0

        try database.execute(
            """
            INSERT INTO provider_ingest_events (
                provider_code, source_mode, provider_session_row_id,
                provider_event_fingerprint, raw_reference_kind,
                raw_reference_event_name, raw_reference_offset,
                observed_at, payload_json, acceptance_state, created_at
            ) VALUES ('claude', ?, ?, ?, 'claude-otel',
                      'claude.api_request', NULL, ?, '{}', 'accepted', ?);
            """,
            bindings: [
                .text(sourceMode), .integer(sessionRowID), .text(fingerprint),
                .text(observedAt), .text(observedAt),
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
            ) VALUES (?, 'claude', ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 1, ?);
            """,
            bindings: [
                .integer(ingestEventRowID), .integer(sessionRowID), .text(observedAt),
                .integer(input), .integer(output), .integer(cached),
                .integer(normalized), .integer(normalized), .text(observedAt),
            ]
        )
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
            Self.makeIntAttr(key: "cached_content_token_count", value: 400),
            Self.makeIntAttr(key: "thoughts_token_count", value: 111),
            Self.makeIntAttr(key: "tool_token_count", value: 222),
            Self.makeIntAttr(key: "total_token_count", value: 2100),
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
        #expect(decoded.totalCachedInputTokens == 400)
        #expect(decoded.normalizedTotalTokens == 2100)
        #expect(decoded.modelSlug == "gemini-2.5-pro")
    }

    @Test
    func claudeOtelInboxWriterAppendsApiRequestUsageSampleWithCacheTokens() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-claude-otel-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let inboxPath = tempDirectory.appendingPathComponent("claude.ndjson").path
        let event = ClaudeOtelSampleEvent(
            sessionID: "claude-session",
            observedAt: ISO8601DateFormatter().date(from: "2026-04-09T14:25:11Z")!,
            model: "claude-sonnet-4-5",
            requestID: "req_123",
            eventSequence: "42",
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 20,
            cacheCreationTokens: 30
        )

        let writer = ClaudeOtelInboxWriter(inboxPath: inboxPath)
        try writer.append(
            event: event,
            cumulativeInputTokens: 100,
            cumulativeOutputTokens: 50,
            cumulativeCachedInputTokens: 50,
            cumulativeNormalizedTotalTokens: 200
        )

        let contents = try String(contentsOfFile: inboxPath, encoding: .utf8)
        let line = contents.split(separator: "\n").first.map(String.init) ?? ""
        let decoded = try JSONDecoder().decode(ProviderUsageSampleEvent.self, from: Data(line.utf8))

        #expect(decoded.provider == .claude)
        #expect(decoded.sourceMode == "claude_otel_api_request_live")
        #expect(decoded.providerSessionID == "claude-session")
        #expect(decoded.modelSlug == "claude-sonnet-4-5")
        #expect(decoded.totalInputTokens == 100)
        #expect(decoded.totalOutputTokens == 50)
        #expect(decoded.totalCachedInputTokens == 50)
        #expect(decoded.normalizedTotalTokens == 200)
        #expect(decoded.currentInputTokens == 100)
        #expect(decoded.currentOutputTokens == 50)
        #expect(decoded.providerEventFingerprint == "claude-otel:claude-session:req_123")
        #expect(decoded.rawReference.kind == "claude-otel")
        #expect(decoded.rawReference.eventName == "claude_code.api_request")
        #expect(decoded.sessionOriginHint == .startedDuringLiveRuntime)
    }

    @Test
    func otelLogsServiceExtractsClaudeApiRequestEventsAndKeepsGeminiSeparated() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-mixed-otel-logs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let geminiInboxPath = tempDirectory.appendingPathComponent("gemini.ndjson").path
        let claudeInboxPath = tempDirectory.appendingPathComponent("claude.ndjson").path
        let service = GeminiOtelLogsService(
            writer: GeminiOtelInboxWriter(inboxPath: geminiInboxPath),
            tracker: GeminiCumulativeTracker(seed: [:]),
            claudeWriter: ClaudeOtelInboxWriter(inboxPath: claudeInboxPath),
            claudeTracker: ClaudeOtelCumulativeTracker(seed: [:])
        )

        var claudeRecord = Opentelemetry_Proto_Logs_V1_LogRecord()
        claudeRecord.timeUnixNano = 1_775_000_100_000_000_000
        claudeRecord.attributes = [
            Self.makeStringAttr(key: "event.name", value: "api_request"),
            Self.makeStringAttr(key: "model", value: "claude-sonnet-4-5"),
            Self.makeStringAttr(key: "request_id", value: "req_abc"),
            Self.makeIntAttr(key: "event.sequence", value: 7),
            Self.makeIntAttr(key: "input_tokens", value: 100),
            Self.makeIntAttr(key: "output_tokens", value: 40),
            Self.makeIntAttr(key: "cache_read_tokens", value: 20),
            Self.makeIntAttr(key: "cache_creation_tokens", value: 10),
        ]

        var claudeResourceLogs = Opentelemetry_Proto_Logs_V1_ResourceLogs()
        claudeResourceLogs.resource.attributes = [
            Self.makeStringAttr(key: "service.name", value: "claude-code"),
            Self.makeStringAttr(key: "session.id", value: "claude-session"),
        ]
        var claudeScopeLogs = Opentelemetry_Proto_Logs_V1_ScopeLogs()
        claudeScopeLogs.logRecords = [claudeRecord]
        claudeResourceLogs.scopeLogs = [claudeScopeLogs]

        var geminiRecord = Opentelemetry_Proto_Logs_V1_LogRecord()
        geminiRecord.timeUnixNano = 1_775_000_200_000_000_000
        geminiRecord.attributes = [
            Self.makeStringAttr(key: "event.name", value: "gemini_cli.api_response"),
            Self.makeStringAttr(key: "session.id", value: "gemini-session"),
            Self.makeStringAttr(key: "model", value: "gemini-2.5-pro"),
            Self.makeIntAttr(key: "input_token_count", value: 25),
            Self.makeIntAttr(key: "output_token_count", value: 5),
            Self.makeIntAttr(key: "total_token_count", value: 30),
        ]
        var geminiScopeLogs = Opentelemetry_Proto_Logs_V1_ScopeLogs()
        geminiScopeLogs.logRecords = [geminiRecord]
        var geminiResourceLogs = Opentelemetry_Proto_Logs_V1_ResourceLogs()
        geminiResourceLogs.scopeLogs = [geminiScopeLogs]

        var request = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest()
        request.resourceLogs = [claudeResourceLogs, geminiResourceLogs]

        try service.handleExportRequestForTesting(request)

        let claudeLine = try String(contentsOfFile: claudeInboxPath, encoding: .utf8)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        let geminiLine = try String(contentsOfFile: geminiInboxPath, encoding: .utf8)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        let claudeDecoded = try JSONDecoder().decode(ProviderUsageSampleEvent.self, from: Data(claudeLine.utf8))
        let geminiDecoded = try JSONDecoder().decode(ProviderUsageSampleEvent.self, from: Data(geminiLine.utf8))

        #expect(claudeDecoded.provider == .claude)
        #expect(claudeDecoded.sourceMode == "claude_otel_api_request_live")
        #expect(claudeDecoded.normalizedTotalTokens == 170)
        #expect(claudeDecoded.totalCachedInputTokens == 30)
        #expect(geminiDecoded.provider == .gemini)
        #expect(geminiDecoded.normalizedTotalTokens == 30)
    }

    @Test
    func cursorUsageCSVAdapterUsesExplicitTotalTokensAndFallsBackToComponentSum() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-cursor-csv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let csvPath = tempDirectory.appendingPathComponent("cursor.csv")
        try """
        Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
        2026-04-18T01:00:00Z,agent-alpha,,agent,gpt-5.4,auto,1400,1000,250,400,1900,$0.12
        2026-04-18T01:05:00Z,agent-alpha,,agent,gpt-5.4,auto,1600,1200,300,500,,$0.16
        """.write(to: csvPath, atomically: true, encoding: .utf8)

        let events = try CursorUsageCSVAdapter.accountUsageEvents(from: csvPath.path)

        #expect(events.count == 2)
        #expect(events[0].provider == .cursor)
        #expect(events[0].sourceMode == "cursor_usage_export_api")
        #expect(events[0].usageKind == "agent")
        #expect(events[0].inputTokens == 1_000)
        #expect(events[0].outputTokens == 400)
        #expect(events[0].cachedInputTokens == 650)
        #expect(events[0].normalizedDeltaTokens == 1_900)
        #expect(events[1].usageKind == "agent")
        #expect(events[1].inputTokens == 1_200)
        #expect(events[1].outputTokens == 500)
        #expect(events[1].cachedInputTokens == 700)
        #expect(events[1].normalizedDeltaTokens == 2_400)
        #expect(events[1].rawReference.kind == "cursor_usage_csv")
    }

    @Test
    func accountUsageIngestionIsStatsOnlyAndDeduplicated() throws {
        let manager = try makeManager(prefix: "tokenmon-account-usage-stats-only")
        let database = try manager.open()
        let observedAt = ISO8601DateFormatter().string(from: Date())
        let event = AccountUsageSampleEvent(
            eventType: "account_usage_sample",
            provider: .cursor,
            sourceMode: "cursor_usage_export_api",
            observedAt: observedAt,
            modelSlug: "gpt-5.4",
            usageKind: "agent",
            inputTokens: 5_000_000,
            outputTokens: 3_000_000,
            cachedInputTokens: 0,
            normalizedDeltaTokens: 8_000_000,
            providerEventFingerprint: "cursor:stats-only:1",
            rawReference: ProviderRawReference(kind: "cursor_usage_csv", offset: "1", eventName: "agent")
        )

        let service = AccountUsageIngestionService(databasePath: manager.path)
        let firstResult = try service.ingestAccountUsageEvents([event], sourceKey: "account-fixture")
        let secondResult = try service.ingestAccountUsageEvents([event], sourceKey: "account-fixture")

        #expect(firstResult.acceptedEvents == 1)
        #expect(firstResult.accountUsageSamplesCreated == 1)
        #expect(secondResult.duplicateEvents == 1)
        #expect(try rowCount(in: "account_usage_samples", database: database) == 1)
        #expect(try rowCount(in: "usage_samples", database: database) == 0)
        #expect(try rowCount(in: "encounters", database: database) == 0)
        #expect(try rowCount(in: "dex_seen", database: database) == 0)
        #expect(try manager.currentRunSummary().totalNormalizedTokens == 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 8_000_000)
    }

    @Test
    func cursorProviderUsageSamplesAreRejectedBeforeGameplayOrLocalUsage() throws {
        let manager = try makeManager(prefix: "tokenmon-cursor-provider-usage-rejected")
        let database = try manager.open()
        try manager.markLiveGameplayStarted(at: "2026-04-24T00:00:00Z")

        let event = ProviderUsageSampleEvent(
            eventType: "provider_usage_sample",
            provider: .cursor,
            sourceMode: "cursor_local_usage_probe",
            providerSessionID: "cursor-session",
            observedAt: "2026-04-24T00:05:00Z",
            workspaceDir: nil,
            modelSlug: "gpt-5.4",
            transcriptPath: nil,
            totalInputTokens: 10_000,
            totalOutputTokens: 5_000,
            totalCachedInputTokens: 0,
            normalizedTotalTokens: 15_000,
            providerEventFingerprint: "cursor:provider-usage:blocked",
            rawReference: ProviderRawReference(kind: "cursor_local_probe", offset: "1", eventName: "token_count"),
            currentInputTokens: 10_000,
            currentOutputTokens: 5_000,
            sessionOriginHint: .startedDuringLiveRuntime
        )

        let result = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            [event],
            sourceKey: "cursor-provider-usage-fixture",
            sourceKind: "ndjson_file"
        )

        #expect(result.acceptedEvents == 0)
        #expect(result.rejectedEvents == 1)
        #expect(result.usageSamplesCreated == 0)
        #expect(try rowCount(in: "usage_samples", database: database) == 0)
        #expect(try rowCount(in: "account_usage_samples", database: database) == 0)
        #expect(try rowCount(in: "encounters", database: database) == 0)
        #expect(try rowCount(in: "dex_seen", database: database) == 0)
        #expect(try rowCount(in: "dex_captured", database: database) == 0)
        #expect(try manager.currentRunSummary().totalNormalizedTokens == 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 0)

        let ingestAudit = try #require(database.fetchOne(
            """
            SELECT acceptance_state, rejection_reason
            FROM provider_ingest_events
            WHERE provider_event_fingerprint = 'cursor:provider-usage:blocked';
            """
        ) { statement in
            (
                state: SQLiteDatabase.columnText(statement, index: 0),
                reason: SQLiteDatabase.columnText(statement, index: 1)
            )
        })
        #expect(ingestAudit.state == "rejected")
        #expect(ingestAudit.reason == "cursor_stats_only_provider_usage_unsupported")

        let cursor = try #require(try manager.providerHealthSummaries().first(where: { $0.provider == .cursor }))
        #expect(cursor.healthState == "missing_configuration")
        #expect(cursor.sourceMode == "cursor_usage_export_api")
        #expect(cursor.lastObservedAt == nil)
        #expect(cursor.reliabilityLabel == "stats_only")
        #expect(cursor.liveGameplayArmed == false)
    }

    @Test
    func tokenStatsPreferAccountUsageByProviderDayAndFallbackToLocalObservedUsage() throws {
        let manager = try makeManager(prefix: "tokenmon-account-usage-precedence")
        let observedAt = ISO8601DateFormatter().string(from: Date())

        let localEvents = [
            ProviderUsageSampleEvent(
                eventType: "provider_usage_sample",
                provider: .codex,
                sourceMode: "codex_session_store_recovery",
                providerSessionID: "local-codex",
                observedAt: observedAt,
                workspaceDir: nil,
                modelSlug: "gpt-5.4",
                transcriptPath: nil,
                totalInputTokens: 100,
                totalOutputTokens: 0,
                totalCachedInputTokens: 0,
                normalizedTotalTokens: 100,
                providerEventFingerprint: "codex:local:1",
                rawReference: ProviderRawReference(kind: "session_store_recovery", offset: "1", eventName: "token_count"),
                currentInputTokens: 100,
                currentOutputTokens: 0
            ),
            ProviderUsageSampleEvent(
                eventType: "provider_usage_sample",
                provider: .claude,
                sourceMode: "claude_statusline_live",
                providerSessionID: "local-claude",
                observedAt: observedAt,
                workspaceDir: nil,
                modelSlug: "claude-opus",
                transcriptPath: nil,
                totalInputTokens: 200,
                totalOutputTokens: 0,
                totalCachedInputTokens: 0,
                normalizedTotalTokens: 200,
                providerEventFingerprint: "claude:local:1",
                rawReference: ProviderRawReference(kind: "statusline", offset: nil, eventName: nil),
                currentInputTokens: 200,
                currentOutputTokens: 0
            ),
        ]
        _ = try UsageSampleIngestionService(databasePath: manager.path).ingestProviderEvents(
            localEvents,
            sourceKey: "local-fixture"
        )

        let accountEvent = AccountUsageSampleEvent(
            eventType: "account_usage_sample",
            provider: .codex,
            sourceMode: "codex_account_usage_fixture",
            observedAt: observedAt,
            modelSlug: "gpt-5.4",
            usageKind: "usage",
            inputTokens: 500,
            outputTokens: 0,
            cachedInputTokens: 0,
            normalizedDeltaTokens: 500,
            providerEventFingerprint: "codex:account:1",
            rawReference: ProviderRawReference(kind: "fixture", offset: "1", eventName: "usage")
        )
        _ = try AccountUsageIngestionService(databasePath: manager.path).ingestAccountUsageEvents(
            [accountEvent],
            sourceKey: "account-fixture"
        )

        let totals = try manager.tokenUsageTotals()
        let providerToday = try manager.tokenByProviderToday()
        let sourceSummary = try manager.tokenUsageSourceSummary()

        #expect(totals.todayTokens == 700)
        #expect(totals.allTimeTokens == 700)
        #expect(providerToday[.codex] == 500)
        #expect(providerToday[.claude] == 200)
        #expect(sourceSummary.hasAccountUsage)
        #expect(sourceSummary.hasLocalUsage)
        #expect(sourceSummary.accountBackedProvidersToday == [.codex])
        #expect(sourceSummary.localOnlyProvidersToday == [.claude])
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
        let server = StubGeminiOtelReceiverServer()
        let supervisor = GeminiOtelReceiverSupervisor(
            dataSource: dataSource,
            inboxPath: inboxPath,
            configuration: GeminiOtelGrpcServer.Configuration(host: "127.0.0.1", port: 0),
            makeServer: { _, _, _ in server }
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
        #expect(server.didStart)
        #expect(server.didStop)
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
            let root = try jsonObject(updatedJSON)
            let telemetry = try #require(root["telemetry"] as? [String: Any])
            #expect(telemetry["enabled"] as? Bool == true)
            #expect(telemetry["target"] as? String == "local")
            #expect(telemetry["otlpEndpoint"] as? String == "http://127.0.0.1:4317")
            #expect(telemetry["logPrompts"] as? Bool == false)
            #expect(root["theme"] as? String == "Xcode")
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
            let telemetry = try #require(jsonObject(updatedJSON)["telemetry"] as? [String: Any])
            #expect(telemetry["otlpEndpoint"] as? String == "http://127.0.0.1:4317")
            #expect(telemetry["logPrompts"] as? Bool == false)
            #expect(telemetry["target"] as? String == "local")
        case .conflict, .alreadyConfigured:
            Issue.record("Expected merged result with allowOverride, got \(result)")
        }
    }

    @Test
    func geminiSettingsMergerRepairsTokenmonEndpointWhenPromptLoggingIsMissingOrEnabled() throws {
        let missingPromptLogging = """
        {
          "telemetry": {
            "enabled": true,
            "target": "local",
            "otlpEndpoint": "http://127.0.0.1:4317",
            "exportInterval": 5000
          }
        }
        """
        let enabledPromptLogging = """
        {
          "telemetry": {
            "enabled": true,
            "target": "local",
            "otlpEndpoint": "http://127.0.0.1:4317",
            "logPrompts": true
          }
        }
        """

        for original in [missingPromptLogging, enabledPromptLogging] {
            let result = try GeminiSettingsMerger.merge(
                existingJSON: original,
                tokenmonHost: "127.0.0.1",
                tokenmonPort: 4317,
                allowOverride: false
            )

            switch result {
            case .merged(let updatedJSON):
                let telemetry = try #require(jsonObject(updatedJSON)["telemetry"] as? [String: Any])
                #expect(telemetry["logPrompts"] as? Bool == false)
                #expect(telemetry["otlpEndpoint"] as? String == "http://127.0.0.1:4317")
                if original.contains("exportInterval") {
                    #expect(telemetry["exportInterval"] as? Int == 5000)
                }
            case .alreadyConfigured, .conflict:
                Issue.record("Expected privacy repair merge, got \(result)")
            }
        }
    }

    @Test
    func geminiSettingsMergerNoOpsWhenAlreadyPointingAtTokenmon() throws {
        let original = """
        {
          "telemetry": {
            "enabled": true,
            "target": "local",
            "otlpEndpoint": "http://127.0.0.1:4317",
            "logPrompts": false
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
    func geminiSettingsMergerPromptLoggingInspectionRequiresExplicitFalse() throws {
        #expect(GeminiSettingsMerger.promptLoggingDisabled(existingJSON: #"{"telemetry":{"logPrompts":false}}"#))
        #expect(GeminiSettingsMerger.promptLoggingDisabled(existingJSON: #"{"telemetry":{"logPrompts":true}}"#) == false)
        #expect(GeminiSettingsMerger.promptLoggingDisabled(existingJSON: #"{"telemetry":{}}"#) == false)
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

    @Test
    func raidDamageCalculatorUsesStatsAndFitBonuses() throws {
        let raid = RaidCatalog.allRaids.first { $0.raidID == "raid_2026_06_logo_vault" }!
        let member = RaidPartyMember(
            speciesID: "CST_TEST",
            assetKey: "cst_test",
            displayName: "Coralcoder",
            field: .coast,
            rarity: .rare,
            slotOrder: 1,
            capturedCount: 4,
            stats: SpeciesStatBlock(
                planning: 2,
                design: 7,
                frontend: 8,
                backend: 4,
                pm: 2,
                infra: 1,
                traits: ["Quick Prototyper", "Clean Coder"]
            )
        )

        let hit = RaidDamageCalculator.memberHit(raid: raid, member: member)

        #expect(hit.roundedAxisScore == 5)
        #expect(hit.roleFitBonus == 1)
        #expect(hit.fieldFitBonus == 1)
        #expect(hit.traitFitBonus == 1)
        #expect(hit.captureBondBonus == 1)
        #expect(hit.baseHitPower == 9)
        #expect(hit.rollOutcome == .normal)
        #expect(hit.rollMultiplier == 1.0)
        #expect(hit.hitPower == 9)
    }

    @Test
    func raidDamageRollsAreDeterministicPerUsageSample() throws {
        let raid = RaidCatalog.allRaids.first { $0.raidID == "raid_2026_06_logo_vault" }!
        let member = RaidPartyMember(
            speciesID: "CST_TEST",
            assetKey: "cst_test",
            displayName: "Coralcoder",
            field: .coast,
            rarity: .rare,
            slotOrder: 1,
            capturedCount: 4,
            stats: SpeciesStatBlock(
                planning: 2,
                design: 7,
                frontend: 8,
                backend: 4,
                pm: 2,
                infra: 1,
                traits: ["Quick Prototyper", "Clean Coder"]
            )
        )

        let first = RaidDamageCalculator.resolveAttack(
            raid: raid,
            partyMembers: [member],
            usageSampleID: 101
        )
        let replay = RaidDamageCalculator.resolveAttack(
            raid: raid,
            partyMembers: [member],
            usageSampleID: 101
        )
        let nextSample = RaidDamageCalculator.resolveAttack(
            raid: raid,
            partyMembers: [member],
            usageSampleID: 102
        )

        #expect(first == replay)
        #expect(first.memberHits.first?.baseHitPower == 9)
        #expect(nextSample.memberHits.first?.baseHitPower == 9)
        #expect(first.memberHits.first?.rollOutcome != nil)
        #expect(nextSample.memberHits.first?.rollOutcome != nil)
    }

    @Test
    func raidTablesAndSeedExistAfterBootstrap() throws {
        let manager = try makeManager(prefix: "raid-bootstrap")
        let database = try manager.open()

        #expect(try rowCount(in: "raid_definitions", database: database) == 11)
        #expect(try rowCount(in: "raid_reward_definitions", database: database) == 10)

        let dashboard = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2026-04-23T00:00:00Z")!
        )
        #expect(dashboard.currentRaid?.raidID == "raid_2026_04_april_vault")
        #expect(dashboard.currentRaid?.maxHP == 12_000)
        #expect(dashboard.archiveEntries.contains { $0.rewardID == "reward_first_spark_trophy" })
        #expect(dashboard.archiveEntries.contains { $0.rewardID == "reward_2026_04_april_relic" })
        #expect(dashboard.archiveEntries.contains { $0.rewardID == "reward_2026_12_december_relic" })
        #expect(dashboard.archiveEntries.first { $0.rewardID == "reward_2026_04_april_relic" }?.status == .available)
        #expect(dashboard.archiveEntries.first { $0.rewardID == "reward_2026_04_april_relic" }?.sourceRaidTargetName == "Clovercore Sentinel")
        #expect(dashboard.archiveEntries.first { $0.rewardID == "reward_2026_04_april_relic" }?.sourceRaidTargetArtKey == "raid_target_token_vault_sentinel")
        #expect(dashboard.archiveEntries.first { $0.rewardID == "reward_2026_05_may_relic" }?.status == .unknown)

        let decemberHP = try database.fetchOne(
            "SELECT max_hp FROM raid_definitions WHERE raid_id = 'raid_2026_12_december_vault';"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }
        #expect(decemberHP == 120_000)
    }

    @Test
    func activeRaidInstanceHPReconcilesWhenSeededDefinitionChanges() throws {
        let manager = try makeManager(prefix: "raid-hp-reconcile")
        let database = try manager.open()

        _ = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2026-04-23T00:00:00Z")!
        )
        try database.execute(
            """
            UPDATE raid_instances
            SET current_hp = 9000,
                total_damage = 1000
            WHERE raid_id = 'raid_2026_04_april_vault';
            """
        )

        let dashboard = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2026-04-23T00:05:00Z")!
        )

        #expect(dashboard.currentRaid?.raidID == "raid_2026_04_april_vault")
        #expect(dashboard.currentRaid?.maxHP == 12_000)
        #expect(dashboard.currentRaid?.currentHP == 11_000)
    }

    @Test
    func newPlayerBlessingBoostsMonthlyRaidDamageForSmallParty() throws {
        let manager = try makeManager(prefix: "raid-new-player-blessing")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-23T00:00:00Z"
        )

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .grassland,
                rarity: .common,
                speciesID: "GRS_001",
                outcome: .captured,
                occurredAt: "2026-04-23T00:00:00Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")

        let service = UsageSampleIngestionService(databasePath: manager.path)
        _ = try service.ingestProviderEvents(
            [
                codexUsageEvent(
                    sessionID: "raid-blessing-session",
                    observedAt: "2026-04-23T00:01:00Z",
                    totalInputTokens: 1_000,
                    totalOutputTokens: 500,
                    fingerprint: "codex:raid-blessing-session:001"
                ),
            ],
            sourceKey: "raid-new-player-blessing",
            sourceKind: "ndjson_file"
        )

        let totalDamage = try database.fetchOne(
            """
            SELECT total_damage
            FROM raid_attacks
            ORDER BY raid_attack_row_id DESC
            LIMIT 1;
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }
        let attackEventPayload = try database.fetchOne(
            """
            SELECT payload_json
            FROM domain_events
            WHERE event_type = 'raid_attack_triggered'
            ORDER BY occurred_at DESC
            LIMIT 1;
            """
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        let dashboard = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2026-04-23T00:02:00Z")!
        )

        #expect(totalDamage == 120)
        #expect(attackEventPayload?.contains("\"damage_blessing_id\":\"first_spark_blessing\"") == true)
        #expect(dashboard.currentRaid?.activeBlessing?.id == "first_spark_blessing")
        #expect(dashboard.currentRaid?.partyPower == 120)
    }

    @Test
    func clearedMonthlyRaidFallsBackToPracticeDisplayDuringActiveMonth() throws {
        let manager = try makeManager(prefix: "raid-cleared-month-display")
        let database = try manager.open()

        _ = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2026-04-23T00:00:00Z")!
        )
        _ = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2027-01-02T00:00:00Z")!
        )

        try database.execute(
            """
            UPDATE raid_instances
            SET status = 'cleared',
                current_hp = 0,
                cleared_at = '2026-04-23T00:01:00Z',
                updated_at = '2026-04-23T00:01:00Z'
            WHERE raid_id IN ('raid_2026_04_april_vault', 'raid_tutorial_first_spark');
            """
        )

        let dashboard = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2026-04-23T00:02:00Z")!
        )

        #expect(dashboard.currentRaid?.raidID == "raid_practice_token_vault")
        #expect(dashboard.currentRaid?.currentHP ?? 0 > 0)
    }

    @Test
    func raidFallsBackToPracticeAfterTutorialClear() throws {
        let manager = try makeManager(prefix: "raid-practice-fallback")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-23T00:00:00Z"
        )

        _ = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2027-01-02T00:00:00Z")!
        )
        try database.execute(
            """
            UPDATE raid_instances
            SET status = 'cleared',
                current_hp = 0,
                cleared_at = '2026-04-23T00:01:00Z',
                updated_at = '2026-04-23T00:01:00Z'
            WHERE raid_id = 'raid_tutorial_first_spark';
            """
        )

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .grassland,
                rarity: .common,
                speciesID: "GRS_001",
                outcome: .captured,
                occurredAt: "2027-01-02T00:00:00Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")

        let service = UsageSampleIngestionService(databasePath: manager.path)
        _ = try service.ingestProviderEvents(
            [
                codexUsageEvent(
                    sessionID: "raid-practice-session",
                    observedAt: "2027-01-02T00:02:00Z",
                    totalInputTokens: 1_000,
                    totalOutputTokens: 500,
                    fingerprint: "codex:raid-practice-session:001"
                ),
            ],
            sourceKey: "raid-practice-fallback",
            sourceKind: "ndjson_file"
        )

        let attackRaidID = try database.fetchOne(
            """
            SELECT raid_id
            FROM raid_attacks
            ORDER BY raid_attack_row_id DESC
            LIMIT 1;
            """
        ) { statement in
            SQLiteDatabase.columnText(statement, index: 0)
        }
        let dashboard = try manager.raidDashboardSummary(
            asOf: ISO8601DateFormatter().date(from: "2027-01-02T00:03:00Z")!
        )

        #expect(attackRaidID == "raid_practice_token_vault")
        #expect(dashboard.currentRaid?.raidID == "raid_practice_token_vault")
        #expect((dashboard.currentRaid?.totalAttacks ?? 0) == 1)
    }

    @Test
    func raidAttackCountFollowsUsageSamplesNotTokenVolume() throws {
        let manager = try makeManager(prefix: "raid-usage-samples")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-04-23T00:00:00Z"
        )

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .grassland,
                rarity: .common,
                speciesID: "GRS_001",
                outcome: .captured,
                occurredAt: "2026-04-23T00:00:00Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")

        let service = UsageSampleIngestionService(databasePath: manager.path)
        _ = try service.ingestProviderEvents(
            [
                codexUsageEvent(
                    sessionID: "raid-session",
                    observedAt: "2026-04-23T00:01:00Z",
                    totalInputTokens: 1_000,
                    totalOutputTokens: 500,
                    fingerprint: "codex:raid-session:001"
                ),
                codexUsageEvent(
                    sessionID: "raid-session",
                    observedAt: "2026-04-23T00:02:00Z",
                    totalInputTokens: 1_000_000,
                    totalOutputTokens: 500_000,
                    fingerprint: "codex:raid-session:002"
                ),
            ],
            sourceKey: "raid-usage-samples",
            sourceKind: "ndjson_file"
        )

        let damages = try database.fetchAll(
            """
            SELECT total_damage
            FROM raid_attacks
            ORDER BY raid_attack_row_id ASC;
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }

        #expect(damages.count == 2)
        #expect(damages.allSatisfy { $0 >= 0 })
        #expect(damages.reduce(0, +) > 0)
    }

    @Test
    func raidClearAcquiresRewardOnce() throws {
        let manager = try makeManager(prefix: "raid-clear")
        let database = try manager.open()
        try upsertStringSetting(
            database: database,
            key: "live_gameplay_started_at",
            value: "2026-03-02T00:00:00Z"
        )

        for speciesID in ["GRS_001", "GRS_002", "GRS_003", "GRS_004", "GRS_005", "GRS_006", "GRS_007", "GRS_008", "GRS_009", "GRS_010"] {
            _ = try manager.forgeEncounter(
                TokenmonDeveloperEncounterForgeRequest(
                    provider: .codex,
                    field: .grassland,
                    rarity: .common,
                    speciesID: speciesID,
                    outcome: .captured,
                    occurredAt: "2026-03-02T00:00:00Z"
                )
            )
            try manager.addToParty(speciesID: speciesID)
        }

        let service = UsageSampleIngestionService(databasePath: manager.path)
        var events: [ProviderUsageSampleEvent] = []
        var runningInput: Int64 = 0
        for index in 1...20 {
            runningInput += 5_000
            events.append(
                codexUsageEvent(
                    sessionID: "raid-clear-session",
                    observedAt: String(format: "2026-03-02T00:%02d:00Z", index),
                    totalInputTokens: runningInput,
                    totalOutputTokens: 1_000,
                    fingerprint: "codex:raid-clear-session:\(index)"
                )
            )
        }
        _ = try service.ingestProviderEvents(
            events,
            sourceKey: "raid-clear",
            sourceKind: "ndjson_file"
        )

        let reward = try database.fetchOne(
            """
            SELECT status, acquired_at
            FROM reward_archive_entries
            WHERE reward_id = 'reward_first_spark_trophy'
            LIMIT 1;
            """
        ) { statement in
            (
                status: SQLiteDatabase.columnText(statement, index: 0),
                acquiredAt: SQLiteDatabase.columnOptionalText(statement, index: 1)
            )
        }

        #expect(reward?.status == RaidRewardArchiveStatus.acquired.rawValue)
        #expect(reward?.acquiredAt != nil)
        #expect(try rowCount(in: "reward_archive_entries", database: database) == 1)
    }
}

private final class StubGeminiReceiverDataSource: GeminiOtelReceiverDataSource {
    func latestGeminiSessionTotals() throws -> [String: GeminiSessionRunningTotals] {
        [:]
    }

    func latestClaudeSessionTotals() throws -> [String: GeminiSessionRunningTotals] {
        [:]
    }
}

private final class StubGeminiOtelReceiverServer: GeminiOtelReceiverServer, @unchecked Sendable {
    private(set) var didStart = false
    private(set) var didStop = false

    func start() async throws {
        didStart = true
    }

    func stop() async throws {
        didStop = true
    }
}
