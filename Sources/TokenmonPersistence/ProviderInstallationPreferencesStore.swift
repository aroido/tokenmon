import Foundation
import TokenmonDomain

public enum CodexConnectionMode: String, CaseIterable, Codable, Sendable {
    case auto
    case accurate

    public var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .accurate:
            return "Accurate"
        }
    }
}

public struct ProviderInstallationPathOverride: Equatable, Codable, Sendable {
    public var executablePath: String?
    public var configurationPath: String?

    public init(
        executablePath: String? = nil,
        configurationPath: String? = nil
    ) {
        self.executablePath = executablePath
        self.configurationPath = configurationPath
    }
}

public struct ProviderInstallationPreferences: Equatable, Codable, Sendable {
    public var claude: ProviderInstallationPathOverride
    public var codex: ProviderInstallationPathOverride
    public var codexMode: CodexConnectionMode

    public init(
        claude: ProviderInstallationPathOverride = ProviderInstallationPathOverride(),
        codex: ProviderInstallationPathOverride = ProviderInstallationPathOverride(),
        codexMode: CodexConnectionMode = .auto
    ) {
        self.claude = claude
        self.codex = codex
        self.codexMode = codexMode
    }

    public func overrides(for provider: ProviderCode) -> ProviderInstallationPathOverride {
        switch provider {
        case .claude:
            return claude
        case .codex:
            return codex
        case .gemini:
            return ProviderInstallationPathOverride()
        case .cursor:
            return ProviderInstallationPathOverride()
        case .openclaw:
            return ProviderInstallationPathOverride()
        }
    }

    public mutating func setExecutablePath(_ path: String?, for provider: ProviderCode) {
        switch provider {
        case .claude:
            claude.executablePath = path?.trimmedNilIfEmpty
        case .codex:
            codex.executablePath = path?.trimmedNilIfEmpty
        case .gemini:
            break
        case .cursor:
            break
        case .openclaw:
            break
        }
    }

    public mutating func setConfigurationPath(_ path: String?, for provider: ProviderCode) {
        switch provider {
        case .claude:
            claude.configurationPath = path?.trimmedNilIfEmpty
        case .codex:
            codex.configurationPath = path?.trimmedNilIfEmpty
        case .gemini:
            break
        case .cursor:
            break
        case .openclaw:
            break
        }
    }

    public mutating func resetOverrides(for provider: ProviderCode) {
        switch provider {
        case .claude:
            claude = ProviderInstallationPathOverride()
        case .codex:
            codex = ProviderInstallationPathOverride()
        case .gemini:
            break
        case .cursor:
            break
        case .openclaw:
            break
        }
    }
}

public extension TokenmonDatabaseManager {
    func providerInstallationPreferences(database providedDatabase: SQLiteDatabase? = nil) throws -> ProviderInstallationPreferences {
        let database = try providedDatabase ?? open()
        let decoder = JSONDecoder()

        guard let rawJSON = try database.fetchOne(
            """
            SELECT setting_value_json
            FROM settings
            WHERE setting_key = 'provider_installation_preferences'
            LIMIT 1;
            """,
            map: { statement in
                SQLiteDatabase.columnText(statement, index: 0)
            }
        ) else {
            return ProviderInstallationPreferences()
        }

        return try decoder.decode(ProviderInstallationPreferences.self, from: Data(rawJSON.utf8))
    }

    func saveProviderInstallationPreferences(_ preferences: ProviderInstallationPreferences) throws {
        let database = try open()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        let encodedValue = try String(decoding: encoder.encode(preferences), as: UTF8.self)

        try database.execute(
            """
            INSERT INTO settings (
                setting_key,
                setting_value_json,
                updated_at
            ) VALUES ('provider_installation_preferences', ?, ?)
            ON CONFLICT(setting_key) DO UPDATE SET
                setting_value_json = excluded.setting_value_json,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(encodedValue),
                .text(updatedAt),
            ]
        )
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
