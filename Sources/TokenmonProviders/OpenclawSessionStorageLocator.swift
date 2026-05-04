import Foundation

public struct OpenclawSessionStorageLocatorConfig: Sendable {
    public let configurationRootPath: String?
    public let environment: [String: String]
    public let homeDirectoryProvider: @Sendable () -> URL

    public init(
        configurationRootPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryProvider: @escaping @Sendable () -> URL = {
            FileManager.default.homeDirectoryForCurrentUser
        }
    ) {
        self.configurationRootPath = configurationRootPath
        self.environment = environment
        self.homeDirectoryProvider = homeDirectoryProvider
    }
}

public enum OpenclawSessionStorageLocator {
    /// Returns the agents root path: ~/.openclaw/agents
    public static func agentsRootPath(
        config: OpenclawSessionStorageLocatorConfig = OpenclawSessionStorageLocatorConfig()
    ) -> String {
        let configurationRoot = resolvedConfigurationRootPath(config: config)
        return URL(fileURLWithPath: configurationRoot, isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .path
    }

    /// Returns the sessions root path used for file watching.
    /// Openclaw stores sessions under ~/.openclaw/agents/<agent-name>/sessions/
    /// We watch the entire agents subtree so we catch all agent session dirs.
    public static func sessionStorageRootPath(
        config: OpenclawSessionStorageLocatorConfig = OpenclawSessionStorageLocatorConfig()
    ) -> String {
        agentsRootPath(config: config)
    }

    private static func resolvedConfigurationRootPath(config: OpenclawSessionStorageLocatorConfig) -> String {
        if let openclawHome = config.environment["OPENCLAW_HOME"]?.trimmedNonEmpty {
            return openclawHome
        }

        if let configurationRootPath = config.configurationRootPath?.trimmedNonEmpty {
            return configurationRootPath
        }

        if let tokenmonHome = config.environment["TOKENMON_HOME_OVERRIDE"]?.trimmedNonEmpty {
            return URL(fileURLWithPath: tokenmonHome, isDirectory: true)
                .appendingPathComponent(".openclaw", isDirectory: true)
                .path
        }

        return config.homeDirectoryProvider()
            .appendingPathComponent(".openclaw", isDirectory: true)
            .path
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
