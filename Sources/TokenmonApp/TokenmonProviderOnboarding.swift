import Foundation
import TokenmonDomain
import TokenmonOtelProviders
import TokenmonPersistence
import TokenmonProviders

struct TokenmonProviderOnboardingStatus: Equatable, Sendable {
    let provider: ProviderCode
    let cliInstalled: Bool
    let isConnected: Bool
    let isPartial: Bool
    let title: String
    let detail: String
    let actionTitle: String?
    let executablePath: String?
    let executableSource: TokenmonProviderDiscoverySource
    let configurationPath: String
    let configurationSource: TokenmonProviderDiscoverySource
    let usesCustomExecutablePath: Bool
    let usesCustomConfigurationPath: Bool
    let codexMode: CodexConnectionMode?
}

struct TokenmonProviderInstallResult: Sendable {
    let provider: ProviderCode
    let message: String
}

struct TokenmonProviderAutoSetupResult: Sendable {
    let provider: ProviderCode
    let configured: Bool
    let message: String
    let error: String?
}

enum TokenmonProviderOnboarding {
    private static let claudeStatusLineWrapperFileName = "tokenmon-statusline.sh"
    private static let claudeStatusLineWrapperMarker = "# tokenmon-claude-statusline-wrapper-v1"
    private static let claudePreviousStatusLineCommandPrefix = "# tokenmon-previous-statusline-command-base64: "
    private static let claudeStatusLineDefaultRefreshInterval = 30
    private static let tokenmonOtelHost = "127.0.0.1"
    private static let tokenmonOtelPort = 4317
    private static let tokenmonOtelEndpoint = "http://127.0.0.1:4317"

    private enum ClaudeOtelSettingsState: Equatable {
        case tokenmonConfigured
        case safeToInstall
        case externalOrSensitive
    }

    static func inspectAll(
        databasePath: String,
        executablePath: String,
        preferences: ProviderInstallationPreferences
    ) -> [TokenmonProviderOnboardingStatus] {
        ProviderCode.allCases.map { provider in
            switch provider {
            case .claude:
                return inspectClaude(
                    databasePath: databasePath,
                    executablePath: executablePath,
                    preferences: preferences
                )
            case .codex:
                return inspectCodex(
                    databasePath: databasePath,
                    executablePath: executablePath,
                    preferences: preferences
                )
            case .gemini:
                return inspectGemini(preferences: preferences)
            case .cursor:
                return inspectCursor(databasePath: databasePath, preferences: preferences)
            case .openclaw:
                return inspectOpenclaw(preferences: preferences)
            }
        }
    }

    static func geminiPromptLoggingDisabled(preferences: ProviderInstallationPreferences) -> Bool {
        let discovery = TokenmonProviderDiscovery.discover(provider: .gemini, preferences: preferences)
        let settingsPath = URL(fileURLWithPath: discovery.configurationPath, isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
        let settingsJSON = (try? String(contentsOfFile: settingsPath, encoding: .utf8)) ?? ""
        return GeminiSettingsMerger.promptLoggingDisabled(existingJSON: settingsJSON)
    }

    static func install(
        provider: ProviderCode,
        databasePath: String,
        executablePath: String,
        preferences: ProviderInstallationPreferences
    ) throws -> TokenmonProviderInstallResult {
        switch provider {
        case .claude:
            return try installClaude(
                databasePath: databasePath,
                executablePath: executablePath,
                preferences: preferences
            )
        case .codex:
            return try installCodex(
                databasePath: databasePath,
                executablePath: executablePath,
                preferences: preferences
            )
        case .gemini:
            return try installGemini(
                databasePath: databasePath,
                executablePath: executablePath,
                preferences: preferences
            )
        case .cursor:
            return TokenmonProviderInstallResult(
                provider: .cursor,
                message: "Cursor sync is managed through scripts/cursor-usage-prototype"
            )
        case .openclaw:
            return installOpenclaw()
        }
    }

    static func autoConfigureDetectedProviders(
        databasePath: String,
        executablePath: String,
        preferences: ProviderInstallationPreferences
    ) -> [TokenmonProviderAutoSetupResult] {
        ProviderCode.allCases.map { provider in
            if provider == .cursor {
                return TokenmonProviderAutoSetupResult(
                    provider: provider,
                    configured: false,
                    message: TokenmonL10n.string("provider.cursor.sync.detail"),
                    error: nil
                )
            }
            if provider == .openclaw {
                return TokenmonProviderAutoSetupResult(
                    provider: provider,
                    configured: false,
                    message: TokenmonL10n.string("provider.install.openclaw.success"),
                    error: nil
                )
            }
            let discovery = TokenmonProviderDiscovery.discover(provider: provider, preferences: preferences)
            guard discovery.executableExists else {
                return TokenmonProviderAutoSetupResult(
                    provider: provider,
                    configured: false,
                    message: TokenmonL10n.format("provider.auto_setup.cli_not_found", provider.displayName),
                    error: nil
                )
            }

            do {
                let result = try install(
                    provider: provider,
                    databasePath: databasePath,
                    executablePath: executablePath,
                    preferences: preferences
                )
                return TokenmonProviderAutoSetupResult(
                    provider: provider,
                    configured: true,
                    message: result.message,
                    error: nil
                )
            } catch {
                return TokenmonProviderAutoSetupResult(
                    provider: provider,
                    configured: false,
                    message: TokenmonL10n.string("provider.auto_setup.failed"),
                    error: error.localizedDescription
                )
            }
        }
    }

    private static func inspectOpenclaw(
        preferences: ProviderInstallationPreferences
    ) -> TokenmonProviderOnboardingStatus {
        let discovery = TokenmonProviderDiscovery.discover(provider: .openclaw, preferences: preferences)
        let cliInstalled = discovery.executableExists

        if cliInstalled == false {
            return TokenmonProviderOnboardingStatus(
                provider: .openclaw,
                cliInstalled: false,
                isConnected: false,
                isPartial: false,
                title: TokenmonL10n.string("provider.openclaw.missing.title"),
                detail: TokenmonL10n.string("provider.openclaw.missing.detail"),
                actionTitle: nil,
                executablePath: discovery.executablePath,
                executableSource: discovery.executableSource,
                configurationPath: discovery.configurationPath,
                configurationSource: discovery.configurationSource,
                usesCustomExecutablePath: discovery.usesCustomExecutablePath,
                usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
                codexMode: nil
            )
        }

        return TokenmonProviderOnboardingStatus(
            provider: .openclaw,
            cliInstalled: true,
            isConnected: true,
            isPartial: false,
            title: TokenmonL10n.string("provider.openclaw.ready.title"),
            detail: TokenmonL10n.string("provider.openclaw.ready.detail"),
            actionTitle: nil,
            executablePath: discovery.executablePath,
            executableSource: discovery.executableSource,
            configurationPath: discovery.configurationPath,
            configurationSource: discovery.configurationSource,
            usesCustomExecutablePath: discovery.usesCustomExecutablePath,
            usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
            codexMode: nil
        )
    }

    private static func installOpenclaw() -> TokenmonProviderInstallResult {
        TokenmonProviderInstallResult(
            provider: .openclaw,
            message: TokenmonL10n.string("provider.install.openclaw.success")
        )
    }

    private static func inspectGemini(
        preferences: ProviderInstallationPreferences
    ) -> TokenmonProviderOnboardingStatus {
        let discovery = TokenmonProviderDiscovery.discover(provider: .gemini, preferences: preferences)
        let cliInstalled = discovery.executableExists

        let settingsPath = URL(fileURLWithPath: discovery.configurationPath, isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
        let settingsJSON = (try? String(contentsOfFile: settingsPath, encoding: .utf8)) ?? ""

        let mergeResult: GeminiSettingsMerger.Result?
        do {
            mergeResult = try GeminiSettingsMerger.merge(
                existingJSON: settingsJSON,
                tokenmonHost: "127.0.0.1",
                tokenmonPort: 4317,
                allowOverride: false
            )
        } catch {
            mergeResult = nil
        }

        let isConnected: Bool
        let actionTitle: String?
        let title: String
        let detail: String

        switch mergeResult {
        case .alreadyConfigured:
            isConnected = true
            actionTitle = nil
            title = TokenmonL10n.string("provider.gemini.connected.title")
            detail = TokenmonL10n.string("provider.gemini.connected.detail")
        case .conflict(let endpoint):
            isConnected = false
            actionTitle = TokenmonL10n.string("provider.gemini.repair.action")
            title = TokenmonL10n.string("provider.gemini.repair.title")
            detail = TokenmonL10n.format("provider.gemini.repair.conflict_detail", endpoint)
        case .merged, .none:
            isConnected = false
            actionTitle = cliInstalled ? TokenmonL10n.string("provider.gemini.repair.action") : nil
            title = cliInstalled ? TokenmonL10n.string("provider.gemini.repair.title") : TokenmonL10n.string("provider.gemini.missing.title")
            detail = cliInstalled
                ? TokenmonL10n.string("provider.gemini.repair.detail")
                : TokenmonL10n.string("provider.gemini.missing.detail")
        }

        return TokenmonProviderOnboardingStatus(
            provider: .gemini,
            cliInstalled: cliInstalled,
            isConnected: isConnected,
            isPartial: false,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            executablePath: discovery.executablePath,
            executableSource: discovery.executableSource,
            configurationPath: discovery.configurationPath,
            configurationSource: discovery.configurationSource,
            usesCustomExecutablePath: discovery.usesCustomExecutablePath,
            usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
            codexMode: nil
        )
    }

    private static func inspectCursor(
        databasePath: String,
        preferences: ProviderInstallationPreferences
    ) -> TokenmonProviderOnboardingStatus {
        let discovery = TokenmonProviderDiscovery.discover(provider: .cursor, preferences: preferences)
        let healthSummary = try? TokenmonDatabaseManager(path: databasePath)
            .providerHealthSummaries()
            .first(where: { $0.provider == .cursor })
        let isConnected = healthSummary?.healthState == "active" || healthSummary?.healthState == "connected"
        return TokenmonProviderOnboardingStatus(
            provider: .cursor,
            cliInstalled: discovery.executableExists,
            isConnected: isConnected,
            isPartial: true,
            title: TokenmonL10n.string(
                isConnected ? "provider.cursor.connected.title" : "provider.cursor.sync.title"
            ),
            detail: TokenmonL10n.string(
                isConnected ? "provider.cursor.connected.detail" : "provider.cursor.sync.detail"
            ),
            actionTitle: TokenmonL10n.string(
                isConnected ? "provider.cursor.sync_again.action" : "provider.cursor.sync.action"
            ),
            executablePath: discovery.executablePath,
            executableSource: discovery.executableSource,
            configurationPath: discovery.configurationPath,
            configurationSource: discovery.configurationSource,
            usesCustomExecutablePath: false,
            usesCustomConfigurationPath: false,
            codexMode: nil
        )
    }

    private static func inspectClaude(
        databasePath _: String,
        executablePath _: String,
        preferences: ProviderInstallationPreferences
    ) -> TokenmonProviderOnboardingStatus {
        let discovery = TokenmonProviderDiscovery.discover(provider: .claude, preferences: preferences)
        let cliInstalled = discovery.executableExists
        guard cliInstalled else {
            return TokenmonProviderOnboardingStatus(
                provider: .claude,
                cliInstalled: false,
                isConnected: false,
                isPartial: false,
                title: TokenmonL10n.string("provider.claude.missing.title"),
                detail: discovery.usesCustomExecutablePath
                    ? TokenmonL10n.string("provider.claude.missing.custom_path_detail")
                    : TokenmonL10n.string("provider.claude.missing.detail"),
                actionTitle: nil,
                executablePath: discovery.executablePath,
                executableSource: discovery.executableSource,
                configurationPath: discovery.configurationPath,
                configurationSource: discovery.configurationSource,
                usesCustomExecutablePath: discovery.usesCustomExecutablePath,
                usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
                codexMode: nil
            )
        }

        let settingsPath = TokenmonProviderDiscovery.claudeSettingsPath(configurationRootPath: discovery.configurationPath)
        let json = loadJSONObject(at: settingsPath) ?? [:]

        let statusLineInstalled = containsTokenmonClaudeStatusLine(
            in: json,
            configurationRootPath: discovery.configurationRootPath
        )
        let statusLineMetadataOnly = containsTokenmonClaudeStatusLineMetadataOnly(
            in: json,
            configurationRootPath: discovery.configurationRootPath
        )
        let statusLineLiveInstalled = statusLineInstalled && statusLineMetadataOnly == false
        let hooksInstalled = containsTokenmonClaudeHooks(in: json)

        let claudeOtelState = claudeOtelSettingsState(in: json)

        if statusLineLiveInstalled && claudeOtelState != .tokenmonConfigured {
            return TokenmonProviderOnboardingStatus(
                provider: .claude,
                cliInstalled: true,
                isConnected: true,
                isPartial: false,
                title: TokenmonL10n.string("provider.claude.connected.title"),
                detail: claudeConnectedDetail(
                    otelState: claudeOtelState,
                    statusLineInstalled: statusLineInstalled,
                    hooksInstalled: hooksInstalled
                ),
                actionTitle: nil,
                executablePath: discovery.executablePath,
                executableSource: discovery.executableSource,
                configurationPath: discovery.configurationPath,
                configurationSource: discovery.configurationSource,
                usesCustomExecutablePath: discovery.usesCustomExecutablePath,
                usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
                codexMode: nil
            )
        }

        return TokenmonProviderOnboardingStatus(
            provider: .claude,
            cliInstalled: true,
            isConnected: true,
            isPartial: false,
            title: TokenmonL10n.string("provider.claude.connected.title"),
            detail: claudeOtelState == .tokenmonConfigured
                ? TokenmonL10n.string("provider.claude.connected.detail_otel_passive_skip")
                : TokenmonL10n.string("provider.claude.connected.detail_passive_transcript"),
            actionTitle: nil,
            executablePath: discovery.executablePath,
            executableSource: discovery.executableSource,
            configurationPath: discovery.configurationPath,
            configurationSource: discovery.configurationSource,
            usesCustomExecutablePath: discovery.usesCustomExecutablePath,
            usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
            codexMode: nil
        )
    }

    private static func inspectCodex(
        databasePath: String,
        executablePath _: String,
        preferences: ProviderInstallationPreferences
    ) -> TokenmonProviderOnboardingStatus {
        let discovery = TokenmonProviderDiscovery.discover(provider: .codex, preferences: preferences)
        let cliInstalled = discovery.executableExists
        guard cliInstalled else {
            return TokenmonProviderOnboardingStatus(
                provider: .codex,
                cliInstalled: false,
                isConnected: false,
                isPartial: false,
                title: TokenmonL10n.string("provider.codex.missing.title"),
                detail: discovery.usesCustomExecutablePath
                    ? TokenmonL10n.string("provider.codex.missing.custom_path_detail")
                    : TokenmonL10n.string("provider.codex.missing.detail"),
                actionTitle: nil,
                executablePath: discovery.executablePath,
                executableSource: discovery.executableSource,
                configurationPath: discovery.configurationPath,
                configurationSource: discovery.configurationSource,
                usesCustomExecutablePath: discovery.usesCustomExecutablePath,
                usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
                codexMode: preferences.codexMode
            )
        }

        if discovery.usesCustomConfigurationPath && discovery.configurationRootExists == false {
            return TokenmonProviderOnboardingStatus(
                provider: .codex,
                cliInstalled: true,
                isConnected: false,
                isPartial: false,
                title: TokenmonL10n.string("provider.codex.path_missing.title"),
                detail: TokenmonL10n.string("provider.codex.path_missing.detail"),
                actionTitle: TokenmonL10n.string("provider.codex.path_missing.action"),
                executablePath: discovery.executablePath,
                executableSource: discovery.executableSource,
                configurationPath: discovery.configurationPath,
                configurationSource: discovery.configurationSource,
                usesCustomExecutablePath: discovery.usesCustomExecutablePath,
                usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
                codexMode: preferences.codexMode
            )
        }

        return TokenmonProviderOnboardingStatus(
            provider: .codex,
            cliInstalled: true,
            isConnected: true,
            isPartial: false,
            title: TokenmonL10n.string("provider.codex.ready.title"),
            detail: TokenmonL10n.string("provider.codex.ready.detail"),
            actionTitle: nil,
            executablePath: discovery.executablePath,
            executableSource: discovery.executableSource,
            configurationPath: discovery.configurationPath,
            configurationSource: discovery.configurationSource,
            usesCustomExecutablePath: discovery.usesCustomExecutablePath,
            usesCustomConfigurationPath: discovery.usesCustomConfigurationPath,
            codexMode: preferences.codexMode
        )
    }

    private static func installClaude(
        databasePath: String,
        executablePath _: String,
        preferences _: ProviderInstallationPreferences
    ) throws -> TokenmonProviderInstallResult {
        try upsertClaudePassiveTranscriptHealth(databasePath: databasePath)

        return TokenmonProviderInstallResult(
            provider: .claude,
            message: TokenmonL10n.string("provider.install.claude.passive_transcript")
        )
    }

    static func shouldStartClaudePassiveTranscriptObserver(
        preferences: ProviderInstallationPreferences
    ) -> Bool {
        let discovery = TokenmonProviderDiscovery.discover(provider: .claude, preferences: preferences)
        let settingsPath = TokenmonProviderDiscovery.claudeSettingsPath(configurationRootPath: discovery.configurationRootPath)
        let json = loadJSONObject(at: settingsPath) ?? [:]

        let statusLineInstalled = containsTokenmonClaudeStatusLine(
            in: json,
            configurationRootPath: discovery.configurationRootPath
        )
        let statusLineMetadataOnly = containsTokenmonClaudeStatusLineMetadataOnly(
            in: json,
            configurationRootPath: discovery.configurationRootPath
        )
        let tokenmonStatusLineLiveInstalled = statusLineInstalled && statusLineMetadataOnly == false

        return tokenmonStatusLineLiveInstalled == false
            && claudeOtelSettingsState(in: json) != .tokenmonConfigured
    }

    private static func upsertClaudePassiveTranscriptHealth(databasePath: String) throws {
        let database = try TokenmonDatabaseManager(path: databasePath).open()
        let updatedAt = ISO8601DateFormatter().string(from: Date())
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
                .text(ProviderCode.claude.rawValue),
                .text("claude_transcript_live"),
                .text("connected"),
                .text("Claude passive transcript monitoring is ready without changing Claude settings"),
                .text(updatedAt),
                .text(updatedAt),
            ]
        )
    }

    private static func installCodex(
        databasePath: String,
        executablePath: String,
        preferences: ProviderInstallationPreferences
    ) throws -> TokenmonProviderInstallResult {
        _ = databasePath
        _ = executablePath
        _ = preferences

        return TokenmonProviderInstallResult(
            provider: .codex,
            message: TokenmonL10n.string("provider.install.codex.success")
        )
    }

    private static func installGemini(
        databasePath _: String,
        executablePath _: String,
        preferences: ProviderInstallationPreferences
    ) throws -> TokenmonProviderInstallResult {
        let discovery = TokenmonProviderDiscovery.discover(provider: .gemini, preferences: preferences)
        let settingsPath = URL(fileURLWithPath: discovery.configurationPath, isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
        let directory = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let existing = (try? String(contentsOfFile: settingsPath, encoding: .utf8)) ?? ""
        try backupIfExists(path: settingsPath)

        let mergeResult: GeminiSettingsMerger.Result
        do {
            mergeResult = try GeminiSettingsMerger.merge(
                existingJSON: existing,
                tokenmonHost: "127.0.0.1",
                tokenmonPort: 4317,
                allowOverride: true
            )
        } catch GeminiSettingsMerger.MergerError.invalidJSON {
            mergeResult = try GeminiSettingsMerger.merge(
                existingJSON: "",
                tokenmonHost: "127.0.0.1",
                tokenmonPort: 4317,
                allowOverride: true
            )
        }

        switch mergeResult {
        case .merged(let updatedJSON):
            try writeString(updatedJSON, to: settingsPath)
            return TokenmonProviderInstallResult(
                provider: .gemini,
                message: TokenmonL10n.string("provider.install.gemini.success")
            )
        case .alreadyConfigured:
            return TokenmonProviderInstallResult(
                provider: .gemini,
                message: TokenmonL10n.string("provider.install.gemini.already_configured")
            )
        case .conflict(let endpoint):
            throw TokenmonProviderInstallError.geminiConflict(existingEndpoint: endpoint)
        }
    }

    private static func installClaudeHook(
        event: String,
        matcher: String?,
        command: String,
        hooks: inout [String: Any]
    ) {
        var matcherGroups = (hooks[event] as? [[String: Any]]) ?? []
        guard matcherGroups.contains(where: { containsCommand($0, command: command) }) == false else {
            hooks[event] = matcherGroups
            return
        }

        var matcherGroup: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                ],
            ],
        ]
        if let matcher {
            matcherGroup["matcher"] = matcher
        }
        matcherGroups.append(matcherGroup)
        hooks[event] = matcherGroups
    }

    private static func containsTokenmonClaudeStatusLine(
        in json: [String: Any],
        configurationRootPath: String
    ) -> Bool {
        tokenmonClaudeStatusLineCommandText(in: json, configurationRootPath: configurationRootPath) != nil
    }

    private static func containsTokenmonClaudeStatusLineMetadataOnly(
        in json: [String: Any],
        configurationRootPath: String
    ) -> Bool {
        tokenmonClaudeStatusLineCommandText(in: json, configurationRootPath: configurationRootPath)?
            .contains("--metadata-only") == true
    }

    private static func tokenmonClaudeStatusLineCommandText(
        in json: [String: Any],
        configurationRootPath: String
    ) -> String? {
        guard let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return nil
        }
        if command.contains("--tokenmon-provider-claude-statusline-import") {
            return command
        }

        guard command.contains(claudeStatusLineWrapperFileName) else {
            return nil
        }

        let wrapperPath = claudeStatusLineWrapperPath(configurationRootPath: configurationRootPath)
        guard let contents = try? String(contentsOfFile: wrapperPath, encoding: .utf8) else {
            return nil
        }
        guard contents.contains(claudeStatusLineWrapperMarker),
              contents.contains("--tokenmon-provider-claude-statusline-import") else {
            return nil
        }
        return "\(command)\n\(contents)"
    }

    private static func containsTokenmonClaudeHooks(in json: [String: Any]) -> Bool {
        guard let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        return ["SessionStart", "SessionEnd", "Notification"].allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else {
                return false
            }
            return groups.contains { containsCommand($0, commandSubstring: "--tokenmon-provider-claude-hook-import") }
        }
    }

    private static func claudeConnectedDetail(
        otelState: ClaudeOtelSettingsState,
        statusLineInstalled: Bool,
        hooksInstalled: Bool
    ) -> String {
        if otelState == .tokenmonConfigured {
            return hooksInstalled
                ? TokenmonL10n.string("provider.claude.connected.detail_otel_with_hooks")
                : TokenmonL10n.string("provider.claude.connected.detail_otel")
        }
        if otelState == .externalOrSensitive, statusLineInstalled {
            return TokenmonL10n.string("provider.claude.connected.detail_external_otel_statusline")
        }
        return hooksInstalled
            ? TokenmonL10n.string("provider.claude.connected.detail_with_hooks")
            : TokenmonL10n.string("provider.claude.connected.detail")
    }

    private static func claudeRepairDetail(
        otelState: ClaudeOtelSettingsState,
        hooksInstalled: Bool
    ) -> String {
        if otelState == .externalOrSensitive {
            return TokenmonL10n.string("provider.claude.repair.external_otel_detail")
        }
        if otelState == .tokenmonConfigured {
            return TokenmonL10n.string("provider.claude.repair.tokenmon_otel_detail")
        }
        return hooksInstalled
            ? TokenmonL10n.string("provider.claude.repair.hooks_only_detail")
            : TokenmonL10n.string("provider.claude.repair.statusline_detail")
    }

    private static func claudeOtelSettingsState(in json: [String: Any]) -> ClaudeOtelSettingsState {
        guard let env = json["env"] as? [String: Any], env.isEmpty == false else {
            return .safeToInstall
        }

        let normalized = env.reduce(into: [String: String]()) { result, entry in
            result[entry.key] = String(describing: entry.value)
        }
        if tokenmonClaudeOtelConfigured(in: normalized) {
            return .tokenmonConfigured
        }

        let hasSensitiveFlag = [
            "OTEL_LOG_USER_PROMPTS",
            "OTEL_LOG_TOOL_DETAILS",
            "OTEL_LOG_TOOL_CONTENT",
            "OTEL_LOG_RAW_API_BODIES",
        ].contains { key in
            truthy(normalized[key])
        }
        if hasSensitiveFlag {
            return .externalOrSensitive
        }

        let hasOtelConfig = normalized.keys.contains { key in
            key == "CLAUDE_CODE_ENABLE_TELEMETRY" || key.hasPrefix("OTEL_")
        }
        return hasOtelConfig ? .externalOrSensitive : .safeToInstall
    }

    private static func tokenmonClaudeOtelConfigured(in env: [String: String]) -> Bool {
        guard truthy(env["CLAUDE_CODE_ENABLE_TELEMETRY"]) else {
            return false
        }
        let logsExporter = env["OTEL_LOGS_EXPORTER"] ?? ""
        guard logsExporter
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .contains("otlp") else {
            return false
        }

        let endpoints = [
            env["OTEL_EXPORTER_OTLP_ENDPOINT"],
            env["OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"],
        ].compactMap { $0 }
        return endpoints.contains(where: isTokenmonOtelEndpoint(_:))
    }

    private static func isTokenmonOtelEndpoint(_ value: String) -> Bool {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized == tokenmonOtelEndpoint ||
            normalized == "http://localhost:\(tokenmonOtelPort)" ||
            normalized == "\(tokenmonOtelHost):\(tokenmonOtelPort)" ||
            normalized == "localhost:\(tokenmonOtelPort)"
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty == false &&
            normalized != "0" &&
            normalized != "false" &&
            normalized != "none"
    }

    private static func removeTokenmonClaudeOtelEnv(into json: inout [String: Any]) {
        var env = (json["env"] as? [String: Any]) ?? [:]
        [
            "CLAUDE_CODE_ENABLE_TELEMETRY",
            "OTEL_LOGS_EXPORTER",
            "OTEL_METRICS_EXPORTER",
            "OTEL_TRACES_EXPORTER",
            "OTEL_EXPORTER_OTLP_PROTOCOL",
            "OTEL_EXPORTER_OTLP_ENDPOINT",
            "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT",
        ].forEach { env.removeValue(forKey: $0) }

        if env.isEmpty {
            json.removeValue(forKey: "env")
        } else {
            json["env"] = env
        }
    }

    private static func containsAppOwnedCodexHooks(configurationRootPath: String) -> Bool {
        guard let json = loadJSONObject(at: TokenmonProviderDiscovery.codexHooksPath(configurationRootPath: configurationRootPath)),
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        return ["SessionStart", "Stop"].allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else {
                return false
            }
            return groups.contains {
                containsCommand($0, commandSubstring: "--tokenmon-provider-codex-hook-import") &&
                    containsLegacyTokenmonCommand($0) == false
            }
        }
    }

    private static func containsLegacyTokenmonCodexHooks(configurationRootPath: String) -> Bool {
        guard let json = loadJSONObject(at: TokenmonProviderDiscovery.codexHooksPath(configurationRootPath: configurationRootPath)),
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .contains(where: containsLegacyTokenmonCommand(_:))
    }

    private static func codexHooksFeatureEnabled(configurationRootPath: String) -> Bool {
        guard let contents = try? String(contentsOfFile: TokenmonProviderDiscovery.codexConfigPath(configurationRootPath: configurationRootPath), encoding: .utf8) else {
            return false
        }
        let lines = contents.components(separatedBy: .newlines)
        var inFeaturesSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inFeaturesSection = trimmed == "[features]"
                continue
            }
            guard inFeaturesSection else {
                continue
            }
            if trimmed.hasPrefix("codex_hooks") {
                return trimmed.contains("true")
            }
        }
        return false
    }

    private static func containsCommand(_ matcherGroup: [String: Any], command: String) -> Bool {
        containsCommand(matcherGroup, commandSubstring: command)
    }

    private static func containsCommand(_ matcherGroup: [String: Any], commandSubstring: String) -> Bool {
        guard let handlers = matcherGroup["hooks"] as? [[String: Any]] else {
            return false
        }
        return handlers.contains { handler in
            guard let command = handler["command"] as? String else {
                return false
            }
            return command.contains(commandSubstring)
        }
    }

    private static func containsLegacyTokenmonCommand(_ matcherGroup: [String: Any]) -> Bool {
        guard let handlers = matcherGroup["hooks"] as? [[String: Any]] else {
            return false
        }

        return handlers.contains { handler in
            guard let command = handler["command"] as? String else {
                return false
            }

            return command.contains("tokenmon --tokenmon-provider-codex-hook-import") ||
                command.contains("tokenmon provider codex hook import")
        }
    }

    private static func mergeCodexFeatureFlag(existingContents: String?) -> String {
        var lines = (existingContents ?? "").components(separatedBy: .newlines)
        var featuresSectionIndex: Int?
        var codexHooksLineIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[features]" {
                featuresSectionIndex = index
                continue
            }

            guard featuresSectionIndex != nil else {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                break
            }

            if trimmed.hasPrefix("codex_hooks") {
                codexHooksLineIndex = index
                break
            }
        }

        if let codexHooksLineIndex {
            lines[codexHooksLineIndex] = "codex_hooks = true"
            return normalizeConfigLines(lines)
        }

        if let featuresSectionIndex {
            let insertionIndex = nextSectionIndex(after: featuresSectionIndex, in: lines) ?? lines.count
            lines.insert("codex_hooks = true", at: insertionIndex)
            return normalizeConfigLines(lines)
        }

        if lines.isEmpty == false, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("codex_hooks = true")
        return normalizeConfigLines(lines)
    }

    private static func nextSectionIndex(after index: Int, in lines: [String]) -> Int? {
        for candidateIndex in lines.index(after: index)..<lines.endIndex {
            let trimmed = lines[candidateIndex].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                return candidateIndex
            }
        }
        return nil
    }

    private static func normalizeConfigLines(_ lines: [String]) -> String {
        var rendered = lines.joined(separator: "\n")
        if rendered.hasSuffix("\n") == false {
            rendered.append("\n")
        }
        return rendered
    }

    private static func mergeCodexHooks(
        existingObject: [String: Any]?,
        command: String
    ) -> [String: Any] {
        var object = existingObject ?? [:]
        var hooks = (object["hooks"] as? [String: Any]) ?? [:]

        hooks = removingTokenmonCodexHooks(from: hooks)

        installCodexHook(event: "SessionStart", matcher: "startup|resume", command: command, timeout: nil, hooks: &hooks)
        installCodexHook(event: "Stop", matcher: nil, command: command, timeout: 2, hooks: &hooks)

        object["hooks"] = hooks
        return object
    }

    private static func removingTokenmonCodexHooks(from hooks: [String: Any]) -> [String: Any] {
        var cleaned = hooks

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                continue
            }

            let filteredGroups = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    return group
                }

                let filteredHandlers = handlers.filter { handler in
                    guard let command = handler["command"] as? String else {
                        return true
                    }
                    return command.contains("--tokenmon-provider-codex-hook-import") == false &&
                        command.contains("tokenmon provider codex hook import") == false
                }

                guard filteredHandlers.isEmpty == false else {
                    return nil
                }

                var filteredGroup = group
                filteredGroup["hooks"] = filteredHandlers
                return filteredGroup
            }

            if filteredGroups.isEmpty {
                cleaned.removeValue(forKey: event)
            } else {
                cleaned[event] = filteredGroups
            }
        }

        return cleaned
    }

    private static func installCodexHook(
        event: String,
        matcher: String?,
        command: String,
        timeout: Int?,
        hooks: inout [String: Any]
    ) {
        var matcherGroups = (hooks[event] as? [[String: Any]]) ?? []
        guard matcherGroups.contains(where: { containsCommand($0, commandSubstring: "--tokenmon-provider-codex-hook-import") }) == false else {
            hooks[event] = matcherGroups
            return
        }

        var hookEntry: [String: Any] = [
            "type": "command",
            "command": command,
        ]
        if let timeout {
            hookEntry["timeout"] = timeout
        }

        var matcherGroup: [String: Any] = [
            "hooks": [hookEntry],
        ]
        if let matcher {
            matcherGroup["matcher"] = matcher
        }
        matcherGroups.append(matcherGroup)
        hooks[event] = matcherGroups
    }

    private static func shellCommand(
        executablePath: String,
        flag: String,
        databasePath: String,
        extraArguments: [String] = []
    ) -> String {
        let extras = extraArguments.isEmpty ? "" : " \(extraArguments.joined(separator: " "))"
        return "\(shellQuote(executablePath)) \(flag) --db \(shellQuote(databasePath))\(extras)"
    }

    private static func claudeStatusLineWrapperPath(configurationRootPath: String) -> String {
        URL(fileURLWithPath: configurationRootPath, isDirectory: true)
            .appendingPathComponent(claudeStatusLineWrapperFileName)
            .path
    }

    private static func preservedClaudeStatusLineCommand(
        from statusLine: [String: Any]?,
        wrapperPath: String,
        backupSettingsPath: String
    ) -> String? {
        guard let command = trimmedNilIfEmpty(statusLine?["command"] as? String) else {
            return nil
        }

        if isTokenmonClaudeStatusLineCommand(command) {
            return readPreviousClaudeStatusLineCommand(from: wrapperPath) ??
                readBackupClaudeStatusLineCommand(from: backupSettingsPath)
        }

        return command
    }

    private static func isTokenmonClaudeStatusLineCommand(_ command: String) -> Bool {
        command.contains("--tokenmon-provider-claude-statusline-import") ||
            command.contains(claudeStatusLineWrapperFileName)
    }

    private static func writeClaudeStatusLineWrapper(
        path: String,
        tokenmonCommand: String,
        previousCommand: String?
    ) throws {
        try writeString(
            claudeStatusLineWrapperContents(
                tokenmonCommand: tokenmonCommand,
                previousCommand: previousCommand
            ),
            to: path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path
        )
    }

    private static func claudeStatusLineWrapperContents(
        tokenmonCommand: String,
        previousCommand: String?
    ) -> String {
        let previousCommand = previousCommand ?? ""
        let previousCommandBase64 = Data(previousCommand.utf8).base64EncodedString()

        return """
        #!/bin/sh
        \(claudeStatusLineWrapperMarker)
        \(claudePreviousStatusLineCommandPrefix)\(previousCommandBase64)
        TOKENMON_STATUSLINE_COMMAND=\(shellQuote(tokenmonCommand))
        TOKENMON_PREVIOUS_STATUSLINE_COMMAND=\(shellQuote(previousCommand))

        payload="$(cat)"
        tokenmon_status="$(
            printf '%s' "$payload" | /bin/sh -c "$TOKENMON_STATUSLINE_COMMAND" 2>/dev/null
        )"
        previous_status=""
        if [ -n "$TOKENMON_PREVIOUS_STATUSLINE_COMMAND" ]; then
            previous_status="$(
                printf '%s' "$payload" | /bin/sh -c "$TOKENMON_PREVIOUS_STATUSLINE_COMMAND" 2>/dev/null
            )"
        fi

        if [ -n "$previous_status" ]; then
            printf '%s\\n' "$previous_status"
        elif [ -n "$tokenmon_status" ]; then
            printf '%s\\n' "$tokenmon_status"
        else
            printf '%s\\n' "Tokenmon waiting for Claude usage"
        fi

        """
    }

    private static func readPreviousClaudeStatusLineCommand(from wrapperPath: String) -> String? {
        guard let contents = try? String(contentsOfFile: wrapperPath, encoding: .utf8),
              contents.contains(claudeStatusLineWrapperMarker) else {
            return nil
        }

        for line in contents.components(separatedBy: .newlines) {
            guard line.hasPrefix(claudePreviousStatusLineCommandPrefix) else {
                continue
            }
            let encoded = String(line.dropFirst(claudePreviousStatusLineCommandPrefix.count))
            guard let data = Data(base64Encoded: encoded),
                  let command = trimmedNilIfEmpty(String(data: data, encoding: .utf8)) else {
                return nil
            }
            return command
        }

        return nil
    }

    private static func readBackupClaudeStatusLineCommand(from backupSettingsPath: String) -> String? {
        guard let json = loadJSONObject(at: backupSettingsPath),
              let statusLine = json["statusLine"] as? [String: Any],
              let command = trimmedNilIfEmpty(statusLine["command"] as? String),
              isTokenmonClaudeStatusLineCommand(command) == false else {
            return nil
        }
        return command
    }

    private static func trimmedNilIfEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func loadJSONObject(at path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeJSONObject(_ object: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func writeString(_ contents: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func backupIfExists(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        let backupPath = backupPath(for: path)
        if FileManager.default.fileExists(atPath: backupPath) == false {
            try FileManager.default.copyItem(atPath: path, toPath: backupPath)
        }
    }

    private static func backupPath(for path: String) -> String {
        "\(path).tokenmon-backup"
    }
}

enum TokenmonProviderInstallError: Error, LocalizedError {
    case geminiConflict(existingEndpoint: String)

    var errorDescription: String? {
        switch self {
        case .geminiConflict(let endpoint):
            return TokenmonL10n.format("provider.gemini.install.conflict_error", endpoint)
        }
    }
}
