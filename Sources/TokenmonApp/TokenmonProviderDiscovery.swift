import Foundation
import TokenmonDomain
import TokenmonPersistence

enum TokenmonProviderDiscoverySource: String, Equatable, Sendable {
    case override
    case bundledDefault
    case commonLocation
    case shellLookup
    case unavailable

    var title: String {
        switch self {
        case .override:
            return "Custom"
        case .bundledDefault:
            return "Default"
        case .commonLocation:
            return "Auto"
        case .shellLookup:
            return "Shell"
        case .unavailable:
            return "Missing"
        }
    }
}

struct TokenmonProviderDiscoveryResult: Equatable, Sendable {
    let provider: ProviderCode
    let executablePath: String?
    let executableExists: Bool
    let executableSource: TokenmonProviderDiscoverySource
    let configurationRootPath: String
    let configurationRootExists: Bool
    let configurationSource: TokenmonProviderDiscoverySource
    let usesCustomExecutablePath: Bool
    let usesCustomConfigurationPath: Bool

    var configurationPath: String { configurationRootPath }
}

enum TokenmonProviderDiscovery {
    static func discover(
        provider: ProviderCode,
        preferences: ProviderInstallationPreferences
    ) -> TokenmonProviderDiscoveryResult {
        let overrides = preferences.overrides(for: provider)
        let executable = discoverExecutable(named: executableName(for: provider), overridePath: overrides.executablePath)
        let configuration = discoverConfigurationRoot(for: provider, overridePath: overrides.configurationPath)

        return TokenmonProviderDiscoveryResult(
            provider: provider,
            executablePath: executable.path,
            executableExists: executable.exists,
            executableSource: executable.source,
            configurationRootPath: configuration.path ?? defaultConfigurationRootPath(for: provider),
            configurationRootExists: configuration.exists,
            configurationSource: configuration.source,
            usesCustomExecutablePath: overrides.executablePath != nil,
            usesCustomConfigurationPath: overrides.configurationPath != nil
        )
    }

    static func claudeSettingsPath(
        preferences: ProviderInstallationPreferences
    ) -> String {
        claudeSettingsPath(configurationRootPath: discover(provider: .claude, preferences: preferences).configurationRootPath)
    }

    static func claudeSettingsPath(configurationRootPath: String) -> String {
        URL(fileURLWithPath: configurationRootPath, isDirectory: true)
            .appendingPathComponent("settings.json")
            .path
    }

    static func codexConfigPath(
        preferences: ProviderInstallationPreferences
    ) -> String {
        codexConfigPath(configurationRootPath: discover(provider: .codex, preferences: preferences).configurationRootPath)
    }

    static func codexConfigPath(configurationRootPath: String) -> String {
        URL(fileURLWithPath: configurationRootPath, isDirectory: true)
            .appendingPathComponent("config.toml")
            .path
    }

    static func codexHooksPath(
        preferences: ProviderInstallationPreferences
    ) -> String {
        codexHooksPath(configurationRootPath: discover(provider: .codex, preferences: preferences).configurationRootPath)
    }

    static func codexHooksPath(configurationRootPath: String) -> String {
        URL(fileURLWithPath: configurationRootPath, isDirectory: true)
            .appendingPathComponent("hooks.json")
            .path
    }

    static func resolvedHomeDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["TOKENMON_HOME_OVERRIDE"],
           override.isEmpty == false {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private struct DiscoveredPath {
        let path: String?
        let exists: Bool
        let source: TokenmonProviderDiscoverySource
    }

    private static func discoverExecutable(
        named executable: String,
        overridePath: String?
    ) -> DiscoveredPath {
        if let overridePath = overridePath?.trimmedNilIfEmpty {
            return DiscoveredPath(
                path: overridePath,
                exists: FileManager.default.isExecutableFile(atPath: overridePath),
                source: .override
            )
        }

        for candidate in candidateExecutablePaths(named: executable) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return DiscoveredPath(path: candidate, exists: true, source: .commonLocation)
            }
        }

        if let shellPath = shellLookupPath(for: executable),
           FileManager.default.isExecutableFile(atPath: shellPath) {
            return DiscoveredPath(path: shellPath, exists: true, source: .shellLookup)
        }

        if executable == "cursor" {
            for candidate in cursorAppExecutableCandidates() {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return DiscoveredPath(path: candidate, exists: true, source: .commonLocation)
                }
            }
        }

        return DiscoveredPath(path: nil, exists: false, source: .unavailable)
    }

    private static func discoverConfigurationRoot(
        for provider: ProviderCode,
        overridePath: String?
    ) -> DiscoveredPath {
        if let overridePath = overridePath?.trimmedNilIfEmpty {
            return DiscoveredPath(
                path: overridePath,
                exists: FileManager.default.fileExists(atPath: overridePath),
                source: .override
            )
        }

        let defaultPath = defaultConfigurationRootPath(for: provider)
        return DiscoveredPath(
            path: defaultPath,
            exists: FileManager.default.fileExists(atPath: defaultPath),
            source: .bundledDefault
        )
    }

    private static func executableName(for provider: ProviderCode) -> String {
        switch provider {
        case .claude:
            return "claude"
        case .codex:
            return "codex"
        case .gemini:
            return "gemini"
        case .cursor:
            return "cursor"
        case .openclaw:
            return "openclaw"
        }
    }

    private static func defaultConfigurationRootPath(for provider: ProviderCode) -> String {
        switch provider {
        case .claude:
            return resolvedHomeDirectory().appendingPathComponent(".claude", isDirectory: true).path
        case .codex:
            return resolvedHomeDirectory().appendingPathComponent(".codex", isDirectory: true).path
        case .gemini:
            return resolvedHomeDirectory().appendingPathComponent(".gemini", isDirectory: true).path
        case .cursor:
            return resolvedHomeDirectory()
                .appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
                .path
        case .openclaw:
            return resolvedHomeDirectory().appendingPathComponent(".openclaw", isDirectory: true).path
        }
    }

    private static func candidateExecutablePaths(named executable: String) -> [String] {
        let home = resolvedHomeDirectory()
        var paths = Set<String>()

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for pathEntry in envPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(pathEntry), isDirectory: true)
                .appendingPathComponent(executable)
                .path
            paths.insert(candidate)
        }

        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            home.appendingPathComponent("bin", isDirectory: true).path,
            home.appendingPathComponent(".local/bin", isDirectory: true).path,
            home.appendingPathComponent(".local/share/mise/shims", isDirectory: true).path,
            home.appendingPathComponent(".asdf/shims", isDirectory: true).path,
            home.appendingPathComponent(".volta/bin", isDirectory: true).path,
            home.appendingPathComponent(".bun/bin", isDirectory: true).path,
            home.appendingPathComponent("Library/pnpm", isDirectory: true).path,
            home.appendingPathComponent(".npm-global/bin", isDirectory: true).path,
            home.appendingPathComponent(".yarn/bin", isDirectory: true).path,
        ]

        if let miseInstalls = miseNodeBinDirectories(home: home) {
            for directory in miseInstalls {
                let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent(executable)
                    .path
                paths.insert(candidate)
            }
        }

        for directory in commonDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executable)
                .path
            paths.insert(candidate)
        }

        return Array(paths).sorted()
    }

    private static func miseNodeBinDirectories(home: URL) -> [String]? {
        let installsRoot = home.appendingPathComponent(".local/share/mise/installs/node", isDirectory: true).path
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: installsRoot) else {
            return nil
        }
        return entries
            .map { (installsRoot as NSString).appendingPathComponent($0) + "/bin" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    private static func shellLookupPath(for executable: String) -> String? {
        let candidateShells = [
            ProcessInfo.processInfo.environment["SHELL"],
            "/bin/zsh",
            "/bin/bash",
        ].compactMap { $0 }

        // -ilc loads both login (.zprofile) and interactive (.zshrc) configs so
        // PATH-modifying tools like mise/asdf/nvm activated in .zshrc are picked up
        // even when tokenmon runs as a GUI app with sparse PATH.
        let invocationArgs: [[String]] = [
            ["-ilc"],
            ["-lc"],
        ]

        for shell in candidateShells {
            for args in invocationArgs {
                if let path = runShellCommand(shell: shell, args: args, executable: executable) {
                    return path
                }
            }
        }

        return nil
    }

    private static func runShellCommand(shell: String, args: [String], executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = args + ["command -v \(shellEscape(executable))"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // -ilc may emit greetings/MOTD; take the last line that looks like an absolute path.
        let lines = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        if let resolved = lines.reversed().first(where: { $0.hasPrefix("/") }) {
            return resolved
        }
        return nil
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func cursorAppExecutableCandidates() -> [String] {
        let home = resolvedHomeDirectory()
        let appRoots = [
            "/Applications/Cursor.app",
            home.appendingPathComponent("Applications/Cursor.app", isDirectory: true).path,
        ]

        return appRoots.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("Contents/MacOS/Cursor")
                .path
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
