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
        }
    }

    private static func candidateExecutablePaths(named executable: String) -> [String] {
        candidateExecutablePaths(named: executable, home: resolvedHomeDirectory())
    }

    static func candidateExecutablePaths(named executable: String, home: URL) -> [String] {
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

        for directory in commonDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executable)
                .path
            paths.insert(candidate)
        }

        for directory in miseNodeBinDirectories(home: home) {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executable)
                .path
            paths.insert(candidate)
        }

        return Array(paths).sorted()
    }

    static func miseNodeBinDirectories(home: URL) -> [String] {
        let installsRoot = home.appendingPathComponent(".local/share/mise/installs/node", isDirectory: true).path
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: installsRoot) else {
            return []
        }
        return entries
            .map { (installsRoot as NSString).appendingPathComponent($0) + "/bin" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Thread-safe accumulator for `readabilityHandler` callbacks, which fire on
    /// an arbitrary background queue.
    private final class ShellLookupBuffer: @unchecked Sendable {
        private let queue = DispatchQueue(label: "tokenmon.shell-lookup.buffer")
        private var data = Data()

        func append(_ chunk: Data) {
            queue.sync { data.append(chunk) }
        }

        func snapshot() -> Data {
            queue.sync { data }
        }
    }

    private static func shellLookupPath(for executable: String) -> String? {
        let candidateShells = [
            ProcessInfo.processInfo.environment["SHELL"],
            "/bin/zsh",
            "/bin/bash",
        ].compactMap { $0 }

        // -lc sources login config (.zprofile) but NOT interactive config (.zshrc),
        // so we avoid executing the user's interactive startup files from a menu bar
        // app. The static candidate paths above cover the common mise/asdf/volta/bun/
        // pnpm setups directly; this fallback exists for users whose PATH is set in
        // .zprofile or other login-time configuration.
        for shell in candidateShells {
            let command = "command -v \(shellEscape(executable))"
            if let path = runShellLookup(
                shell: shell,
                args: ["-lc", command],
                terminateAfter: 2.0,
                killAfter: 2.5
            ) {
                return path
            }
        }

        return nil
    }

    /// Runs a bounded shell subprocess to resolve an executable path.
    ///
    /// Hardening:
    /// - Sends SIGTERM after `terminateAfter` seconds, escalates to SIGKILL after
    ///   `killAfter` seconds. This prevents a slow or blocking login config from
    ///   stalling provider discovery indefinitely.
    /// - Drains stdout/stderr asynchronously via `readabilityHandler` so a noisy
    ///   `.zprofile` cannot fill the 64KB pipe buffer and block the child on write.
    /// - Buffer mutation is serialized on a dedicated queue because
    ///   `readabilityHandler` fires on an arbitrary queue.
    /// - Limitation: signals are delivered to the shell PID only; children forked
    ///   from the login config (rare in `.zprofile`) may outlive the shell. The
    ///   bounded read window + SIGKILL escalation keep the practical impact small.
    static func runShellLookup(
        shell: String,
        args: [String],
        terminateAfter: TimeInterval,
        killAfter: TimeInterval
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let buffer = ShellLookupBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            // Drain to prevent the child from blocking on stderr writes; discard.
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let terminateItem = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
        let killItem = DispatchWorkItem { [weak process] in
            guard let process, process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + terminateAfter, execute: terminateItem)
        DispatchQueue.global().asyncAfter(deadline: .now() + killAfter, execute: killItem)

        process.waitUntilExit()
        terminateItem.cancel()
        killItem.cancel()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        guard process.terminationStatus == 0,
              process.terminationReason == .exit else {
            return nil
        }

        let snapshot = buffer.snapshot()
        let output = String(decoding: snapshot, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A noisy login config can emit banners before `command -v` prints its
        // result, so pick the last absolute-path line rather than trusting the
        // whole capture.
        let lines = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        return lines.reversed().first { $0.hasPrefix("/") }
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
