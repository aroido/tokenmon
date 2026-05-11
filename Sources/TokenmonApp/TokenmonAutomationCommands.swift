import Foundation
import TokenmonDomain
import TokenmonPersistence
import TokenmonProviders

enum TokenmonAutomationCommand {
    static func runIfRequested(arguments: [String]) throws -> String? {
        if arguments.contains("--tokenmon-db-init") {
            return try runDatabaseCommand(mode: "init", arguments: arguments)
        }
        if arguments.contains("--tokenmon-db-reset-progress") {
            return try runDatabaseCommand(mode: "reset-progress", arguments: arguments)
        }
        if arguments.contains("--tokenmon-db-maintenance") {
            return try runDatabaseCommand(mode: "maintenance", arguments: arguments)
        }
        if arguments.contains("--tokenmon-seed-species") {
            return try runSeedCommand(arguments: arguments)
        }
        if let inboxPath = optionValue("--tokenmon-ingest-inbox", in: arguments) {
            return try runIngestCommand(inboxPath: inboxPath, arguments: arguments)
        }
        if let accountUsagePath = optionValue("--tokenmon-ingest-account-usage", in: arguments) {
            return try runAccountUsageIngestCommand(accountUsagePath: accountUsagePath, arguments: arguments)
        }
        if arguments.contains("--tokenmon-summary") {
            return try runSummaryCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-status") {
            return try runStatusCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-watch") {
            return try runWatchCommand(arguments: arguments)
        }
        if let dexMode = optionValue("--tokenmon-dex", in: arguments) {
            return try runDexCommand(mode: dexMode, arguments: arguments)
        }
        if arguments.contains("--tokenmon-diagnose") {
            return try runDiagnoseCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-forge-encounter") {
            return try runForgeEncounterCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-localization-diagnose") {
            return try runLocalizationDiagnoseCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-launch-at-login-status") {
            return try runLaunchAtLoginStatusCommand(arguments: arguments)
        }
        if let mode = optionValue("--tokenmon-launch-at-login-set", in: arguments) {
            return try runLaunchAtLoginSetCommand(mode: mode, arguments: arguments)
        }
        if let mode = optionValue("--tokenmon-launch-at-login-force-native-set", in: arguments) {
            return try runLaunchAtLoginForceNativeSetCommand(mode: mode, arguments: arguments)
        }
        if arguments.contains("--tokenmon-updater-status") {
            return try runUpdaterStatusCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-updater-write-override") {
            return try runUpdaterWriteOverrideCommand(arguments: arguments)
        }
        if arguments.contains("--tokenmon-updater-clear-override") {
            return try runUpdaterClearOverrideCommand(arguments: arguments)
        }
        if let provider = optionValue("--tokenmon-backfill", in: arguments) {
            return try runBackfillCommand(providerRawValue: provider, arguments: arguments)
        }
        if let sourcePath = optionValue("--tokenmon-provider-codex-exec-json-import", in: arguments) {
            return try runCodexExecJSONImport(sourcePath: sourcePath, arguments: arguments)
        }
        if let sourcePath = optionValue("--tokenmon-provider-cursor-import-csv", in: arguments) {
            return try runCursorUsageCSVImport(sourcePath: sourcePath, arguments: arguments)
        }
        if let prompt = optionValue("--tokenmon-provider-codex-exec-json-run", in: arguments) {
            return try runCodexExecJSONRun(prompt: prompt, arguments: arguments)
        }
        if arguments.contains("--tokenmon-provider-claude-statusline-import") {
            return try runClaudeStatusLineImport(arguments: arguments)
        }
        if arguments.contains("--tokenmon-provider-claude-hook-import") {
            return try runClaudeHookImport(arguments: arguments)
        }
        if arguments.contains("--tokenmon-provider-codex-hook-import") {
            return try runCodexHookImport(arguments: arguments)
        }
        if let provider = providerConnectTarget(arguments: arguments) {
            return try runProviderConnect(provider: provider, arguments: arguments)
        }
        return nil
    }

    private static func runDatabaseCommand(mode: String, arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let databaseManager = TokenmonDatabaseManager(path: dbPath)

        switch mode {
        case "init":
            try databaseManager.bootstrap()
            return "initialized database at \(dbPath)"
        case "reset-progress":
            try databaseManager.resetProgress()
            return "reset gameplay progress at \(dbPath)"
        case "maintenance":
            let result = try databaseManager.performMaintenance()
            return [
                "database maintenance complete",
                "file_size_before: \(result.fileSizeBytesBefore)",
                "file_size_after: \(result.fileSizeBytesAfter)",
                "freelist_pages_before: \(result.freelistPagesBefore)",
                "freelist_pages_after: \(result.freelistPagesAfter)",
            ].joined(separator: "\n")
        default:
            throw AutomationError.invalidUsage("unsupported database mode: \(mode)")
        }
    }

    private static func runSeedCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let result = try SpeciesSeeder.seed(databasePath: dbPath)
        return "seeded species: total=\(result.totalSpecies) inserted=\(result.insertedSpecies)"
    }

    private static func runIngestCommand(inboxPath: String, arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let sourceKey = optionValue("--source-key", in: arguments)
        let service = UsageSampleIngestionService(databasePath: dbPath)
        let result = try service.ingestInboxFile(at: inboxPath, sourceKey: sourceKey)

        return [
            "ingest complete",
            "source_key: \(result.sourceKey)",
            "accepted: \(result.acceptedEvents)",
            "duplicates: \(result.duplicateEvents)",
            "rejected: \(result.rejectedEvents)",
            "partial_trailing: \(result.partialTrailingLines)",
            "usage_samples: \(result.usageSamplesCreated)",
            "checkpoint_offset: \(result.lastOffset)",
            "checkpoint_line: \(result.lastLineNumber)",
        ].joined(separator: "\n")
    }

    private static func runAccountUsageIngestCommand(accountUsagePath: String, arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let sourceKey = optionValue("--source-key", in: arguments)
        let service = AccountUsageIngestionService(databasePath: dbPath)
        let result = try service.ingestAccountUsageFile(at: accountUsagePath, sourceKey: sourceKey)

        return [
            "account usage ingest complete",
            "source_key: \(result.sourceKey)",
            "accepted: \(result.acceptedEvents)",
            "duplicates: \(result.duplicateEvents)",
            "rejected: \(result.rejectedEvents)",
            "partial_trailing: \(result.partialTrailingLines)",
            "account_usage_samples: \(result.accountUsageSamplesCreated)",
        ].joined(separator: "\n")
    }

    private static func runSummaryCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let summary = try TokenmonDatabaseManager(path: dbPath).summary()

        return [
            "database summary",
            "providers: \(summary.providers)",
            "provider_sessions: \(summary.providerSessions)",
            "ingest_sources: \(summary.ingestSources)",
            "provider_ingest_events: \(summary.providerIngestEvents)",
            "usage_samples: \(summary.usageSamples)",
            "account_usage_samples: \(summary.accountUsageSamples)",
            "species: \(summary.species)",
            "domain_events: \(summary.domainEvents)",
            "total_normalized_tokens: \(summary.totalNormalizedTokens)",
            "tokens_since_last_encounter: \(summary.tokensSinceLastEncounter)",
            "next_encounter_threshold_tokens: \(summary.nextEncounterThresholdTokens)",
            "tokens_until_next_encounter: \(summary.tokensUntilNextEncounter)",
            "total_encounters: \(summary.totalEncounters)",
            "total_captures: \(summary.totalCaptures)",
            "gameplay_started_at: \(summary.gameplayStartedAt)",
            "live_gameplay_started_at: \(summary.liveGameplayStartedAt ?? "none")",
        ].joined(separator: "\n")
    }

    private static func runStatusCommand(arguments: [String]) throws -> String {
        let recentLimit = try intOptionValue("--recent-limit", in: arguments) ?? 5
        guard recentLimit >= 0 else {
            throw AutomationError.invalidUsage("--recent-limit must be zero or greater")
        }

        let queries = AutomationQueryAdapter(databasePath: optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath())
        let verbosity = try resolvedVerbosity(arguments: arguments)
        let summary = try queries.currentRunSummary()
        let encounters = try queries.recentEncounterSummaries(limit: recentLimit)
        let providerHealth = verbosity == .verbose ? try queries.providerHealthSummaries() : []
        return renderStatus(
            summary: summary,
            encounters: encounters,
            providerHealth: providerHealth,
            verbosity: verbosity
        )
    }

    private static func runWatchCommand(arguments: [String]) throws -> String {
        let iterations = try intOptionValue("--iterations", in: arguments) ?? 0
        let intervalMilliseconds = try intOptionValue("--interval-ms", in: arguments) ?? 1000
        let recentLimit = try intOptionValue("--recent-limit", in: arguments) ?? 3

        guard iterations >= 0 else {
            throw AutomationError.invalidUsage("--iterations must be zero or greater")
        }
        guard intervalMilliseconds >= 0 else {
            throw AutomationError.invalidUsage("--interval-ms must be zero or greater")
        }
        guard recentLimit >= 0 else {
            throw AutomationError.invalidUsage("--recent-limit must be zero or greater")
        }

        let queries = AutomationQueryAdapter(databasePath: optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath())
        let targetIterations = iterations == 0 ? Int.max : iterations
        let verbosity = try resolvedVerbosity(arguments: arguments)
        var renderedIterations: [String] = []

        for iteration in 1...targetIterations {
            let summary = try queries.currentRunSummary()
            let encounters = try queries.recentEncounterSummaries(limit: recentLimit)
            let providerHealth = verbosity == .verbose ? try queries.providerHealthSummaries() : []
            let iterationLabel = iterations == 0 ? "\(iteration)/open" : "\(iteration)/\(targetIterations)"

            renderedIterations.append(
                [
                    "watch iteration \(iterationLabel)",
                    renderStatus(
                        summary: summary,
                        encounters: encounters,
                        providerHealth: providerHealth,
                        verbosity: verbosity
                    ),
                ].joined(separator: "\n")
            )

            if iteration == targetIterations {
                break
            }

            Thread.sleep(forTimeInterval: Double(intervalMilliseconds) / 1000)
        }

        return renderedIterations.joined(separator: "\n\n")
    }

    private static func runDexCommand(mode: String, arguments: [String]) throws -> String {
        let queries = AutomationQueryAdapter(databasePath: optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath())

        switch mode {
        case "seen":
            return renderDex(title: "dex seen", entries: try queries.dexSeenSummaries())
        case "captured":
            return renderDex(title: "dex captured", entries: try queries.dexCapturedSummaries())
        default:
            throw AutomationError.invalidUsage("expected `--tokenmon-dex <seen|captured>`")
        }
    }

    private static func runDiagnoseCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let databaseManager = TokenmonDatabaseManager(path: dbPath)
        let providerHealth = try databaseManager.providerHealthSummaries()
        let preferences = (try? databaseManager.providerInstallationPreferences()) ?? ProviderInstallationPreferences()
        var lines = ["provider diagnose"]

        guard providerHealth.isEmpty == false else {
            lines.append("no providers found")
            return lines.joined(separator: "\n")
        }

        for summary in providerHealth {
            lines.append("")
            lines.append("[\(summary.provider.rawValue)]")
            lines.append("support_level: \(summary.supportLevel)")
            lines.append("reliability_label: \(summary.reliabilityLabel)")
            lines.append("source_mode: \(summary.sourceMode ?? "unknown")")
            lines.append("health_state: \(summary.healthState)")
            lines.append("message: \(summary.message)")
            lines.append("offline_dashboard_recovery: \(summary.offlineDashboardRecovery)")
            lines.append("live_gameplay_armed: \(summary.liveGameplayArmed ? "yes" : "no")")
            if summary.provider == .gemini {
                lines.append(
                    "prompt_logging_disabled: \(TokenmonProviderOnboarding.geminiPromptLoggingDisabled(preferences: preferences) ? "yes" : "no")"
                )
            }
            for key in summary.diagnosticFacts.keys.sorted() {
                lines.append("\(key): \(summary.diagnosticFacts[key] ?? "")")
            }
            lines.append("last_event_time: \(summary.lastObservedAt ?? "none")")
            lines.append("last_success_at: \(summary.lastSuccessAt ?? "none")")
            lines.append("last_error_at: \(summary.lastErrorAt ?? "none")")
            lines.append("last_error: \(summary.lastErrorSummary ?? "none")")
            lines.append("last_backfill_mode: \(summary.lastBackfillMode ?? "none")")
            lines.append("last_backfill_status: \(summary.lastBackfillStatus ?? "none")")
            lines.append("last_backfill_completed_at: \(summary.lastBackfillCompletedAt ?? "none")")
            lines.append("last_backfill_summary: \(summary.lastBackfillSummary ?? "none")")
            lines.append("next_step: \(nextStep(for: summary))")
        }

        if let latestBalancedEvent = try databaseManager.recentProviderIngestEventSummaries(limit: 12)
            .first(where: { $0.gameplayBalanceBucket != nil }) {
            lines.append("")
            lines.append("latest gameplay balance")
            lines.append("provider: \(latestBalancedEvent.provider.rawValue)")
            lines.append("source_mode: \(latestBalancedEvent.sourceMode)")
            lines.append("bucket: \(latestBalancedEvent.gameplayBalanceBucket ?? "none")")
            lines.append("gameplay_delta_tokens: \(latestBalancedEvent.gameplayDeltaTokens ?? 0)")
            if let weight = latestBalancedEvent.gameplayBalanceWeight {
                lines.append("weight: \(String(format: "%.4f", weight))")
            }
            lines.append("policy: \(latestBalancedEvent.gameplayBalancePolicy ?? "none")")
        }

        lines.append("")
        lines.append("idle footprint")
        lines.append("inbox_ingest_mode: checkpointed file reads plus recovery scans and app startup replay")
        lines.append("menubar_refresh_mode: on-launch, inbox file-watch debounce, and manual refresh")
        lines.append("assessment: lightweight by default")
        return lines.joined(separator: "\n")
    }

    private static func runForgeEncounterCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        guard let providerRawValue = optionValue("--provider", in: arguments),
              let provider = ProviderCode(rawValue: providerRawValue) else {
            throw AutomationError.invalidUsage("expected `--provider <claude|codex|gemini>`")
        }
        guard let fieldRawValue = optionValue("--field", in: arguments),
              let field = FieldType(rawValue: fieldRawValue) else {
            throw AutomationError.invalidUsage("expected `--field <grassland|ice|coast|sky>`")
        }
        guard let rarityRawValue = optionValue("--rarity", in: arguments),
              let rarity = RarityTier(rawValue: rarityRawValue) else {
            throw AutomationError.invalidUsage("expected `--rarity <common|uncommon|rare|epic|legendary>`")
        }
        guard let speciesID = optionValue("--species-id", in: arguments), speciesID.isEmpty == false else {
            throw AutomationError.invalidUsage("missing required --species-id <id>")
        }
        guard let outcomeRawValue = optionValue("--outcome", in: arguments),
              let outcome = EncounterOutcome(rawValue: outcomeRawValue) else {
            throw AutomationError.invalidUsage("expected `--outcome <captured|escaped>`")
        }

        let occurredAt = optionValue("--occurred-at", in: arguments) ?? ISO8601DateFormatter().string(from: Date())
        let burstIntensityBand = try intOptionValue("--burst-intensity-band", in: arguments) ?? 2
        let encounter = try TokenmonDatabaseManager(path: dbPath).forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: provider,
                field: field,
                rarity: rarity,
                speciesID: speciesID,
                outcome: outcome,
                occurredAt: occurredAt,
                burstIntensityBand: burstIntensityBand
            )
        )

        return [
            "forged encounter",
            "encounter_id: \(encounter.encounterID)",
            "species_id: \(encounter.speciesID)",
            "field: \(encounter.field.rawValue)",
            "rarity: \(encounter.rarity.rawValue)",
            "outcome: \(encounter.outcome.rawValue)",
        ].joined(separator: "\n")
    }

    private static func runLocalizationDiagnoseCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let settings = try TokenmonDatabaseManager(path: dbPath).appSettings()
        TokenmonL10n.setLocaleOverride(settings.languagePreference.localeIdentifier)

        var lines = ["localization diagnose"]
        lines.append("stored_language_preference: \(settings.languagePreference.rawValue)")

        for (key, value) in TokenmonL10n.diagnosticSnapshot().sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }

        return lines.joined(separator: "\n")
    }

    private static func runLaunchAtLoginStatusCommand(arguments: [String]) throws -> String {
        _ = arguments
        let state = TokenmonLaunchAtLoginController.snapshot()
        return renderLaunchAtLoginState(state, header: "launch_at_login_status")
    }

    private static func runLaunchAtLoginSetCommand(mode: String, arguments: [String]) throws -> String {
        _ = arguments
        let normalizedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let desiredValue: Bool
        switch normalizedMode {
        case "true", "on", "enable", "enabled", "1":
            desiredValue = true
        case "false", "off", "disable", "disabled", "0":
            desiredValue = false
        default:
            throw AutomationError.invalidUsage("expected `--tokenmon-launch-at-login-set <on|off>`")
        }

        do {
            let state = try TokenmonLaunchAtLoginController.setEnabled(desiredValue)
            return renderLaunchAtLoginState(
                state,
                header: "launch_at_login_set",
                extraLines: ["requested: \(desiredValue ? "on" : "off")"]
            )
        } catch {
            let nsError = error as NSError
            var lines = [
                "launch_at_login_set",
                "requested: \(desiredValue ? "on" : "off")",
                "result: error",
                "error_domain: \(nsError.domain)",
                "error_code: \(nsError.code)",
                "error_description: \(nsError.localizedDescription)",
            ]
            if let failureReason = nsError.localizedFailureReason {
                lines.append("failure_reason: \(failureReason)")
            }
            let fallbackState = TokenmonLaunchAtLoginController.snapshot()
            lines.append(contentsOf: renderLaunchAtLoginStateLines(fallbackState))
            return lines.joined(separator: "\n")
        }
    }

    private static func runLaunchAtLoginForceNativeSetCommand(mode: String, arguments: [String]) throws -> String {
        _ = arguments
        let normalizedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let desiredValue: Bool
        switch normalizedMode {
        case "true", "on", "enable", "enabled", "1":
            desiredValue = true
        case "false", "off", "disable", "disabled", "0":
            desiredValue = false
        default:
            throw AutomationError.invalidUsage("expected `--tokenmon-launch-at-login-force-native-set <on|off>`")
        }

        let dependencies = TokenmonLaunchAtLoginDependencies.live()
        do {
            try dependencies.nativeSetter(desiredValue)
            let state = TokenmonLaunchAtLoginController.snapshot(using: dependencies)
            return renderLaunchAtLoginState(
                state,
                header: "launch_at_login_force_native_set",
                extraLines: [
                    "requested: \(desiredValue ? "on" : "off")",
                    "result: success",
                ]
            )
        } catch {
            let nsError = error as NSError
            let state = TokenmonLaunchAtLoginController.snapshot(using: dependencies)
            var lines = [
                "launch_at_login_force_native_set",
                "requested: \(desiredValue ? "on" : "off")",
                "result: error",
                "error_domain: \(nsError.domain)",
                "error_code: \(nsError.code)",
                "error_description: \(nsError.localizedDescription)",
            ]
            if let failureReason = nsError.localizedFailureReason {
                lines.append("failure_reason: \(failureReason)")
            }
            lines.append(contentsOf: renderLaunchAtLoginStateLines(state))
            return lines.joined(separator: "\n")
        }
    }

    private static func renderLaunchAtLoginState(
        _ state: TokenmonLaunchAtLoginState,
        header: String,
        extraLines: [String] = []
    ) -> String {
        var lines = [header]
        lines.append(contentsOf: extraLines)
        lines.append(contentsOf: renderLaunchAtLoginStateLines(state))
        return lines.joined(separator: "\n")
    }

    private static func renderLaunchAtLoginStateLines(
        _ state: TokenmonLaunchAtLoginState
    ) -> [String] {
        [
            "is_supported: \(state.isSupported ? "yes" : "no")",
            "is_enabled: \(state.isEnabled ? "yes" : "no")",
            "shows_open_system_settings_action: \(state.showsOpenSystemSettingsAction ? "yes" : "no")",
            "reason: \(state.reason)",
        ]
    }

    private static func runUpdaterStatusCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let diagnostics = TokenmonAppUpdaterDiagnosticsSnapshot.resolve(databasePath: dbPath)

        var lines = [
            "updater status",
            "availability: \(diagnostics.isAvailable ? "available" : "unavailable")",
            "feed_source: \(diagnostics.feedURLSource?.rawValue ?? "none")",
            "public_ed_key_source: \(diagnostics.publicEDKeySource?.rawValue ?? "none")",
            "override_file_path: \(diagnostics.overrideFilePath)",
            "override_file_present: \(diagnostics.overrideFileExists ? "yes" : "no")",
            "custom_configuration_active: \(diagnostics.hasNonBundledConfiguration ? "yes" : "no")",
        ]

        if let configuredFeedURL = diagnostics.configuredFeedURL {
            lines.append("configured_feed_url: \(configuredFeedURL.absoluteString)")
        }

        if let reason = diagnostics.unavailabilityReason {
            lines.append("reason: \(reason)")
        }

        if let overrideLoadErrorDescription = diagnostics.overrideLoadErrorDescription {
            lines.append("override_file_error: \(overrideLoadErrorDescription)")
        }

        return lines.joined(separator: "\n")
    }

    private static func runUpdaterWriteOverrideCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let feedURL = optionValue("--feed-url", in: arguments)
        let publicEDKey = try resolvedPublicEDKey(arguments: arguments)

        guard feedURL != nil || publicEDKey != nil else {
            throw AutomationError.invalidUsage(
                "expected `--tokenmon-updater-write-override` with `--feed-url <url>` and/or `--public-ed-key <key>`"
            )
        }

        let existingOverride = try TokenmonAppUpdaterOverrideStore.load(databasePath: dbPath) ?? TokenmonAppUpdaterOverride()
        let mergedOverride = TokenmonAppUpdaterOverride(
            feedURL: feedURL ?? existingOverride.feedURL,
            publicEDKey: publicEDKey ?? existingOverride.publicEDKey
        )

        let overrideFilePath = try TokenmonAppUpdaterOverrideStore.save(mergedOverride, databasePath: dbPath)
        let diagnostics = TokenmonAppUpdaterDiagnosticsSnapshot.resolve(databasePath: dbPath)

        var lines = [
            "updater override written",
            "override_file_path: \(overrideFilePath)",
            "availability: \(diagnostics.isAvailable ? "available" : "unavailable")",
            "feed_source: \(diagnostics.feedURLSource?.rawValue ?? "none")",
            "public_ed_key_source: \(diagnostics.publicEDKeySource?.rawValue ?? "none")",
        ]

        if let configuredFeedURL = diagnostics.configuredFeedURL {
            lines.append("configured_feed_url: \(configuredFeedURL.absoluteString)")
        }

        if let reason = diagnostics.unavailabilityReason {
            lines.append("reason: \(reason)")
        }

        lines.append("next_step: restart Tokenmon to apply the updated Sparkle configuration")
        return lines.joined(separator: "\n")
    }

    private static func runUpdaterClearOverrideCommand(arguments: [String]) throws -> String {
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let removed = try TokenmonAppUpdaterOverrideStore.clear(databasePath: dbPath)
        let diagnostics = TokenmonAppUpdaterDiagnosticsSnapshot.resolve(databasePath: dbPath)

        var lines = [
            "updater override cleared",
            "removed: \(removed ? "yes" : "no")",
            "availability: \(diagnostics.isAvailable ? "available" : "unavailable")",
            "feed_source: \(diagnostics.feedURLSource?.rawValue ?? "none")",
            "public_ed_key_source: \(diagnostics.publicEDKeySource?.rawValue ?? "none")",
            "override_file_path: \(diagnostics.overrideFilePath)",
        ]

        if let configuredFeedURL = diagnostics.configuredFeedURL {
            lines.append("configured_feed_url: \(configuredFeedURL.absoluteString)")
        }

        if let reason = diagnostics.unavailabilityReason {
            lines.append("reason: \(reason)")
        }

        lines.append("next_step: restart Tokenmon to return to the bundled Sparkle configuration")
        return lines.joined(separator: "\n")
    }

    private static func runBackfillCommand(providerRawValue: String, arguments: [String]) throws -> String {
        guard let provider = ProviderCode(rawValue: providerRawValue) else {
            throw AutomationError.invalidUsage("expected `--tokenmon-backfill <claude|codex>`")
        }
        guard let transcriptPath = optionValue("--transcript", in: arguments) else {
            throw AutomationError.invalidUsage("missing required --transcript <path>")
        }

        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let sessionID = optionValue("--session-id", in: arguments)

        switch provider {
        case .claude:
            let result = try ClaudeTranscriptBackfillService.run(
                databasePath: dbPath,
                providerSessionID: sessionID,
                transcriptPath: transcriptPath
            )
            return [
                "backfill run complete",
                "provider: \(provider.rawValue)",
                "mode: transcript_backfill",
                "status: \(result.status)",
                "backfill_run_id: \(result.backfillRunID == 0 ? "none" : "\(result.backfillRunID)")",
                "session_id: \(result.sessionID ?? "unknown")",
                "samples_examined: \(result.samplesExamined)",
                "samples_created: \(result.samplesCreated)",
                "duplicates_skipped: \(result.duplicatesSkipped)",
                "errors_count: \(result.errorsCount)",
                "collapsed_duplicate_messages: \(result.collapsedDuplicateMessages)",
                "summary_json: \(result.summaryJSON)",
            ].joined(separator: "\n")
        case .codex:
            let result = try CodexTranscriptBackfillService.run(
                databasePath: dbPath,
                providerSessionID: sessionID,
                transcriptPath: transcriptPath
            )
            return [
                "backfill run complete",
                "provider: \(provider.rawValue)",
                "mode: transcript_backfill",
                "status: \(result.status)",
                "backfill_run_id: \(result.backfillRunID)",
                "session_id: \(result.sessionID ?? "unknown")",
                "samples_examined: \(result.samplesExamined)",
                "samples_created: \(result.samplesCreated)",
                "duplicates_skipped: \(result.duplicatesSkipped)",
                "errors_count: \(result.errorsCount)",
                "summary_json: \(result.summaryJSON)",
            ].joined(separator: "\n")
        case .gemini:
            throw AutomationError.invalidUsage("gemini transcript backfill is not yet supported")
        case .cursor:
            throw AutomationError.invalidUsage("cursor transcript backfill is not yet supported")
        case .openclaw:
            throw AutomationError.invalidUsage("openclaw transcript backfill is not yet supported")
        }
    }

    private static func runProviderConnect(
        provider: ProviderCode,
        arguments: [String]
    ) throws -> String {
        let databasePath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let executablePath = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let preferences = try TokenmonDatabaseManager(path: databasePath).providerInstallationPreferences()
        let result = try TokenmonProviderOnboarding.install(
            provider: provider,
            databasePath: databasePath,
            executablePath: executablePath,
            preferences: preferences
        )

        return """
        provider_connect: ok
        provider: \(result.provider.rawValue)
        message: \(result.message)
        """
    }

    private static func runClaudeStatusLineImport(arguments: [String]) throws -> String {
        let payloadJSON = try inputJSON(arguments: arguments)
        let outputPath = arguments.contains("--metadata-only")
            ? nil
            : optionValue("--out", in: arguments) ??
                TokenmonDatabaseManager.inboxPath(provider: .claude, databasePath: optionValue("--db", in: arguments))
        let verbose = arguments.contains("--verbose")
        let result = try ClaudeStatusLineAdapter.importPayload(
            json: payloadJSON,
            outputPath: outputPath
        )

        var lines = [result.renderedStatusLine]
        if verbose {
            lines.append("claude statusline import complete")
            lines.append("session_id: \(result.sessionID)")
            lines.append("transcript_path: \(result.transcriptPath ?? "none")")
            lines.append("normalized_total_tokens: \(result.normalizedTotalTokens)")
            lines.append("provider_event_fingerprint: \(result.providerEventFingerprint)")
            if let outputPath = result.outputPath {
                lines.append("output_path: \(outputPath)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func runClaudeHookImport(arguments: [String]) throws -> String {
        let payloadJSON = try inputJSON(arguments: arguments)
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let verbose = arguments.contains("--verbose")
        let hookPayload = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(payloadJSON.utf8))
        let importResult = try ClaudeHookAdapter.importPayload(json: payloadJSON)
        let persistenceResult = try ClaudeHookEnrichmentStore.apply(
            databasePath: dbPath,
            payload: hookPayload
        )

        var lines = [
            "claude hook import complete",
            "hook_event_name: \(importResult.hookEventName)",
            "session_id: \(importResult.sessionID)",
        ]
        if let message = importResult.message {
            lines.append("message: \(message)")
        }
        if verbose {
            lines.append("session_state: \(persistenceResult.sessionState)")
            lines.append("health_state: \(persistenceResult.healthState)")
            lines.append("provider_session_row_id: \(persistenceResult.providerSessionRowID)")
        }
        return lines.joined(separator: "\n")
    }

    private static func runCodexHookImport(arguments: [String]) throws -> String {
        let payloadJSON = try inputJSON(arguments: arguments)
        let dbPath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        let verbose = arguments.contains("--verbose")
        let hookPayload: CodexHookPayload
        let importResult: CodexHookImportResult
        do {
            hookPayload = try JSONDecoder().decode(CodexHookPayload.self, from: Data(payloadJSON.utf8))
            importResult = try CodexHookAdapter.importPayload(json: payloadJSON)
        } catch {
            return renderIgnoredCodexHookImport(payloadJSON: payloadJSON, error: error, verbose: verbose)
        }
        let persistenceResult = try CodexHookEnrichmentStore.apply(
            databasePath: dbPath,
            payload: hookPayload
        )
        try TokenmonInboxActivitySignal.touchCodexHookSignal(databasePath: dbPath)

        var lines = [
            "codex hook import complete",
            "hook_event_name: \(importResult.hookEventName)",
            "session_id: \(importResult.sessionID)",
        ]
        if let model = importResult.model {
            lines.append("model: \(model)")
        }
        if verbose {
            lines.append("session_state: \(persistenceResult.sessionState)")
            lines.append("health_state: \(persistenceResult.healthState)")
            lines.append("provider_session_row_id: \(persistenceResult.providerSessionRowID)")
            lines.append("transcript_backfill_status: \(persistenceResult.transcriptBackfillStatus ?? "none")")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderIgnoredCodexHookImport(
        payloadJSON: String,
        error: Error,
        verbose: Bool
    ) -> String {
        let metadata = codexHookMetadata(from: payloadJSON)
        let reason: String
        if payloadJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reason = "empty payload"
        } else if metadata["hook_event_name"] == nil {
            reason = "invalid JSON"
        } else if metadata["session_id"] == nil {
            reason = "missing session_id"
        } else {
            reason = "invalid payload"
        }

        var lines = ["codex hook import ignored"]
        if let hookEventName = metadata["hook_event_name"] {
            lines.append("hook_event_name: \(hookEventName)")
        }
        if let sessionID = metadata["session_id"] {
            lines.append("session_id: \(sessionID)")
        }
        if let model = metadata["model"] {
            lines.append("model: \(model)")
        }
        lines.append("reason: \(reason)")
        if verbose {
            lines.append("error: \(String(describing: error))")
        }
        return lines.joined(separator: "\n")
    }

    private static func runCodexExecJSONImport(sourcePath: String, arguments: [String]) throws -> String {
        let outputPath = optionValue("--out", in: arguments)
        let workspaceDirOverride = optionValue("--workspace-dir", in: arguments)
        let sessionIDFallback = optionValue("--session-id", in: arguments)
        let result = try CodexExecJSONAdapter.importJSONL(
            from: sourcePath,
            outputPath: outputPath,
            config: CodexExecJSONAdapterConfig(
                workspaceDirOverride: workspaceDirOverride,
                sessionIDFallback: sessionIDFallback
            )
        )
        return renderCodexExecJSONResult(action: "import", result: result)
    }

    private static func runCursorUsageCSVImport(sourcePath: String, arguments: [String]) throws -> String {
        let outputPath = optionValue("--out", in: arguments)
            ?? TokenmonDatabaseManager.accountUsagePath(provider: .cursor, databasePath: optionValue("--db", in: arguments))
        let result = try CursorUsageCSVAdapter.importCSV(
            from: sourcePath,
            outputPath: outputPath
        )

        return [
            "cursor usage csv import complete",
            "source_path: \(result.sourcePath)",
            "output_path: \(result.outputPath ?? "stdout")",
            "lines_read: \(result.linesRead)",
            "events_written: \(result.eventsWritten)",
        ].joined(separator: "\n")
    }

    private static func runCodexExecJSONRun(prompt: String, arguments: [String]) throws -> String {
        let outputPath = optionValue("--out", in: arguments) ?? TokenmonDatabaseManager.inboxPath(provider: .codex)
        let codexBin = optionValue("--codex-bin", in: arguments) ?? "codex"
        let workingDirectory = optionValue("--cwd", in: arguments)
        let model = optionValue("--model", in: arguments)
        let result = try CodexExecJSONAdapter.runCodexExecJSON(
            prompt: prompt,
            outputPath: outputPath,
            codexBin: codexBin,
            model: model,
            workingDirectory: workingDirectory,
            config: CodexExecJSONAdapterConfig(
                workspaceDirOverride: workingDirectory
            )
        )
        return renderCodexExecJSONResult(action: "run", result: result)
    }

    private static func renderStatus(
        summary: CurrentRunSummary,
        encounters: [RecentEncounterSummary],
        providerHealth: [ProviderHealthSummary],
        verbosity: AutomationTextVerbosity
    ) -> String {
        var lines = [
            "current run",
            "provider_sessions: \(summary.providerSessions)",
            "usage_samples: \(summary.usageSamples)",
            "total_normalized_tokens: \(summary.totalNormalizedTokens)",
            "tokens_since_last_encounter: \(summary.tokensSinceLastEncounter)",
            "next_encounter_threshold_tokens: \(summary.nextEncounterThresholdTokens)",
            "tokens_until_next_encounter: \(summary.tokensUntilNextEncounter)",
            "total_encounters: \(summary.totalEncounters)",
            "total_captures: \(summary.totalCaptures)",
            "dex_seen: \(summary.seenSpeciesCount)",
            "dex_captured: \(summary.capturedSpeciesCount)",
            "recent_encounters: \(summary.totalEncounters)",
        ]

        guard verbosity != .compact else {
            return lines.joined(separator: "\n")
        }

        if encounters.isEmpty == false {
            lines.append("recent_encounter_feed:")
            for encounter in encounters {
                let displayName = TokenmonDexPresentation.visibleSpeciesName(for: encounter, style: .sentence)
                lines.append(
                    "- \(encounter.occurredAt) | \(displayName) | field=\(encounter.field.rawValue) | rarity=\(encounter.rarity.rawValue) | outcome=\(encounter.outcome.rawValue)"
                )
            }
        }

        guard verbosity == .verbose else {
            return lines.joined(separator: "\n")
        }

        lines.append("provider_health:")
        for summary in providerHealth {
            lines.append(
                "- \(summary.provider.rawValue) | support=\(summary.supportLevel) | reliability=\(summary.reliabilityLabel) | mode=\(summary.sourceMode ?? "unknown") | state=\(summary.healthState) | next=\(nextStep(for: summary))"
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func renderDex<Entry: AutomationDexSummaryLike>(title: String, entries: [Entry]) -> String {
        var lines = [title, "entries: \(entries.count)"]

        guard entries.isEmpty == false else {
            lines.append("empty")
            return lines.joined(separator: "\n")
        }

        for (index, entry) in entries.enumerated() {
            let displayName = entry.isNameUnlocked
                ? entry.speciesName
                : "Unknown species"
            var pieces = [
                "\(index + 1). \(displayName)",
                "id=\(entry.speciesID)",
                "field=\(entry.field.rawValue)",
                "rarity=\(entry.rarity.rawValue)",
                "count=\(entry.count)",
            ]
            if let affinity = entry.affinitySummary {
                pieces.append(affinity)
            }
            pieces.append("first=\(entry.firstRecordedAt)")
            pieces.append("last=\(entry.lastRecordedAt)")
            lines.append(pieces.joined(separator: " | "))
        }

        return lines.joined(separator: "\n")
    }

    private static func renderCodexExecJSONResult(action: String, result: CodexExecJSONImportResult) -> String {
        var lines = [
            "codex exec json \(action) complete",
            "thread_id: \(result.threadID ?? "unknown")",
            "lines_read: \(result.linesRead)",
            "events_written: \(result.eventsWritten)",
            "duplicate_turns_skipped: \(result.duplicateTurnsSkipped)",
        ]
        if let sourcePath = result.sourcePath {
            lines.append("source_path: \(sourcePath)")
        }
        if let outputPath = result.outputPath {
            lines.append("output_path: \(outputPath)")
        }
        return lines.joined(separator: "\n")
    }

    private static func resolvedVerbosity(arguments: [String]) throws -> AutomationTextVerbosity {
        guard let rawValue = optionValue("--verbosity", in: arguments) else {
            return .standard
        }
        guard let verbosity = AutomationTextVerbosity(rawValue: rawValue) else {
            throw AutomationError.invalidUsage("expected `--verbosity <compact|standard|verbose>`")
        }
        return verbosity
    }

    private static func inputJSON(arguments: [String]) throws -> String {
        if let inputPath = optionValue("--input", in: arguments) {
            return try String(contentsOfFile: inputPath, encoding: .utf8)
        }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private static func resolvedPublicEDKey(arguments: [String]) throws -> String? {
        let inlineValue = optionValue("--public-ed-key", in: arguments)
        let filePath = optionValue("--public-ed-key-file", in: arguments)

        if inlineValue != nil && filePath != nil {
            throw AutomationError.invalidUsage("use either `--public-ed-key` or `--public-ed-key-file`, not both")
        }

        if let inlineValue {
            return inlineValue
        }

        guard let filePath else {
            return nil
        }

        return try String(contentsOfFile: filePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func codexHookMetadata(from payloadJSON: String) -> [String: String] {
        guard let data = payloadJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var metadata: [String: String] = [:]
        if let hookEventName = object["hook_event_name"] as? String, hookEventName.isEmpty == false {
            metadata["hook_event_name"] = hookEventName
        }
        if let sessionID = object["session_id"] as? String, sessionID.isEmpty == false {
            metadata["session_id"] = sessionID
        }
        if let model = object["model"] as? String, model.isEmpty == false {
            metadata["model"] = model
        }
        return metadata
    }

    private static func optionValue(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private static func intOptionValue(_ flag: String, in arguments: [String]) throws -> Int? {
        guard let value = optionValue(flag, in: arguments) else {
            return nil
        }
        guard let parsed = Int(value) else {
            throw AutomationError.invalidUsage("expected integer value for \(flag), got `\(value)`")
        }
        return parsed
    }

    private static func providerConnectTarget(arguments: [String]) -> ProviderCode? {
        guard let index = arguments.firstIndex(of: "--tokenmon-provider-connect") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return ProviderCode(rawValue: arguments[valueIndex])
    }

    private static func nextStep(for summary: ProviderHealthSummary) -> String {
        switch (summary.provider, summary.healthState) {
        case (.claude, "missing_configuration"):
            return "Tokenmon watches Claude transcripts passively; check Claude transcript persistence if live updates are missing"
        case (.codex, "missing_configuration"):
            return "Codex is watched automatically; inspect the local session store path if live updates are missing"
        case (.gemini, "missing_configuration"):
            return "Tokenmon should configure Gemini automatically; repair Gemini if telemetry is still unavailable"
        case (.cursor, "missing_configuration"):
            return "Sync Cursor usage from Tokenmon to import the latest managed-only accounting data."
        case (_, "experimental"):
            return "inspect transcript activity and repair the provider from the app"
        case (_, "degraded"):
            return "inspect provider state and run recovery from Tokenmon Developer tools"
        case (_, "unsupported"):
            return "reconnect the provider from Tokenmon"
        default:
            return "monitor recent provider activity"
        }
    }
}

private enum AutomationTextVerbosity: String {
    case compact
    case standard
    case verbose
}

private struct AutomationQueryAdapter {
    private let databaseManager: TokenmonDatabaseManager

    init(databasePath: String) {
        databaseManager = TokenmonDatabaseManager(path: databasePath)
    }

    func currentRunSummary() throws -> CurrentRunSummary {
        try databaseManager.currentRunSummary()
    }

    func recentEncounterSummaries(limit: Int) throws -> [RecentEncounterSummary] {
        try databaseManager.recentEncounterSummaries(limit: limit)
    }

    func dexSeenSummaries() throws -> [DexSeenSummaryEntry] {
        try databaseManager.dexSeenSummaries()
    }

    func dexCapturedSummaries() throws -> [DexCapturedSummaryEntry] {
        try databaseManager.dexCapturedSummaries()
    }

    func providerHealthSummaries() throws -> [ProviderHealthSummary] {
        try databaseManager.providerHealthSummaries()
    }
}

private protocol AutomationDexSummaryLike {
    var speciesID: String { get }
    var speciesName: String { get }
    var field: FieldType { get }
    var rarity: RarityTier { get }
    var firstRecordedAt: String { get }
    var lastRecordedAt: String { get }
    var count: Int64 { get }
    var isNameUnlocked: Bool { get }
    var affinitySummary: String? { get }
}

extension DexSeenSummaryEntry: AutomationDexSummaryLike {
    fileprivate var firstRecordedAt: String { firstSeenAt }
    fileprivate var lastRecordedAt: String { lastSeenAt }
    fileprivate var count: Int64 { seenCount }
    fileprivate var isNameUnlocked: Bool { capturedCount > 0 }
    fileprivate var affinitySummary: String? { nil }
}

extension DexCapturedSummaryEntry: AutomationDexSummaryLike {
    fileprivate var firstRecordedAt: String { firstCapturedAt }
    fileprivate var lastRecordedAt: String { lastCapturedAt }
    fileprivate var count: Int64 { capturedCount }
    fileprivate var isNameUnlocked: Bool { true }
    fileprivate var affinitySummary: String? {
        "affinity=\(TokenmonDexPresentation.affinityLevelLabel(level: affinityLevel)) resonance=\(affinityPityCount)"
    }
}

private enum AutomationError: Error, LocalizedError {
    case invalidUsage(String)

    var errorDescription: String? {
        switch self {
        case .invalidUsage(let message):
            return message
        }
    }
}

enum TokenmonInboxActivitySignal {
    static func touchCodexHookSignal(databasePath: String) throws {
        let signalPath = URL(
            fileURLWithPath: TokenmonDatabaseManager.inboxDirectory(forDatabasePath: databasePath),
            isDirectory: true
        )
        .appendingPathComponent("codex-hook.signal")

        try FileManager.default.createDirectory(
            at: signalPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ISO8601DateFormatter().string(from: Date()).write(
            to: signalPath,
            atomically: true,
            encoding: .utf8
        )
    }
}
