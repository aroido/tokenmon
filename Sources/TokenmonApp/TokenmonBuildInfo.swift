import Foundation

enum TokenmonBuildConfiguration: Equatable, Sendable {
    case debug
    case release

    static var current: TokenmonBuildConfiguration {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }
}

struct TokenmonBuildInfo: Equatable, Sendable {
    let marketingVersion: String?
    let buildNumber: String?
    let branch: String?
    let commitShortHash: String?
    let hasLocalModifications: Bool
    let buildConfiguration: TokenmonBuildConfiguration
    let developerToolsVisibilityOverride: Bool?
    let buildDate: Date?

    static let current = resolve()

    init(
        marketingVersion: String?,
        buildNumber: String?,
        branch: String?,
        commitShortHash: String?,
        hasLocalModifications: Bool,
        buildConfiguration: TokenmonBuildConfiguration,
        developerToolsVisibilityOverride: Bool? = nil,
        buildDate: Date? = nil
    ) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.branch = branch
        self.commitShortHash = commitShortHash
        self.hasLocalModifications = hasLocalModifications
        self.buildConfiguration = buildConfiguration
        self.developerToolsVisibilityOverride = developerToolsVisibilityOverride
        self.buildDate = buildDate
    }

    var versionSummary: String {
        switch (normalized(marketingVersion), normalized(buildNumber)) {
        case let (version?, build?) where build != version:
            return "v\(version) (\(build))"
        case let (version?, _):
            return "v\(version)"
        case let (_, build?):
            return "build \(build)"
        default:
            return "Workspace build"
        }
    }

    var revisionSummary: String {
        guard let commit = normalized(commitShortHash) else {
            return "Unavailable"
        }

        let commitLabel = hasLocalModifications ? "\(commit) + local edits" : commit
        guard let branch = normalized(branch), branch != "HEAD" else {
            return commitLabel
        }

        return "\(branch) @ \(commitLabel)"
    }

    var toolbarLabel: String {
        let baseLabel: String
        if let version = normalized(marketingVersion) {
            baseLabel = "v\(version)"
        } else if let build = normalized(buildNumber) {
            baseLabel = "build \(build)"
        } else {
            baseLabel = "dev"
        }

        guard let commit = normalized(commitShortHash) else {
            return baseLabel
        }

        return hasLocalModifications ? "\(baseLabel) · \(commit)+" : "\(baseLabel) · \(commit)"
    }

    func toolbarBadgeLabel(
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let buildTime = formattedBuildTimestamp(format: "MM-dd HH:mm", timeZone: timeZone) else {
            return toolbarLabel
        }

        return "\(toolbarLabel) · \(buildTime)"
    }

    var accessibilityLabel: String {
        if let buildTimestampSummary {
            return "Build \(versionSummary), \(revisionSummary), built \(buildTimestampSummary)"
        }

        return "Build \(versionSummary), \(revisionSummary)"
    }

    var buildTimestampSummary: String? {
        formattedBuildTimestamp()
    }

    var developerToolsVisible: Bool {
        developerToolsVisibilityOverride ?? (buildConfiguration == .debug)
    }

    static func resolve(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> TokenmonBuildInfo {
        let metadata = TokenmonGitMetadata.resolve(fileManager: fileManager, bundle: bundle)

        return TokenmonBuildInfo(
            marketingVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            branch: bundleString(bundle, key: "TokenmonGitBranch") ?? metadata?.branch,
            commitShortHash: bundleString(bundle, key: "TokenmonGitCommitShort") ?? metadata?.commitShortHash,
            hasLocalModifications: bundleBool(bundle, key: "TokenmonGitDirty") ?? metadata?.hasLocalModifications ?? false,
            buildConfiguration: .current,
            developerToolsVisibilityOverride: developerToolsVisibilityOverride(processInfo),
            buildDate: executableModificationDate(bundle: bundle, fileManager: fileManager)
        )
    }

    func formattedBuildTimestamp(
        format: String = "yyyy-MM-dd HH:mm:ss z",
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let buildDate else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: buildDate)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bundleString(_ bundle: Bundle, key: String) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bundleBool(_ bundle: Bundle, key: String) -> Bool? {
        if let value = bundle.object(forInfoDictionaryKey: key) as? Bool {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: key) as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func environmentBool(_ processInfo: ProcessInfo, key: String) -> Bool? {
        guard let value = processInfo.environment[key] else {
            return nil
        }

        return boolValue(value)
    }

    private static func developerToolsVisibilityOverride(_ processInfo: ProcessInfo) -> Bool? {
        if processInfo.arguments.contains("--tokenmon-developer-tools-visible") {
            return true
        }
        if processInfo.arguments.contains("--tokenmon-developer-tools-hidden") {
            return false
        }

        return environmentBool(processInfo, key: "TOKENMON_DEVELOPER_TOOLS_VISIBLE")
    }

    private static func boolValue(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "on":
            return true
        case "false", "no", "0", "off":
            return false
        default:
            return nil
        }
    }

    private static func executableModificationDate(
        bundle: Bundle,
        fileManager: FileManager
    ) -> Date? {
        guard let executablePath = bundle.executableURL?.path else {
            return nil
        }

        let attributes = try? fileManager.attributesOfItem(atPath: executablePath)
        return attributes?[.modificationDate] as? Date
    }
}

private struct TokenmonGitMetadata: Equatable, Sendable {
    let branch: String?
    let commitShortHash: String?
    let hasLocalModifications: Bool

    static func resolve(
        fileManager: FileManager,
        bundle: Bundle
    ) -> TokenmonGitMetadata? {
        for candidate in candidateDirectories(fileManager: fileManager, bundle: bundle) {
            guard let repositoryRoot = repositoryRoot(containing: candidate) else {
                continue
            }

            guard let commit = runGit(["-C", repositoryRoot.path, "rev-parse", "--short", "HEAD"]) else {
                continue
            }

            let branch = runGit(["-C", repositoryRoot.path, "rev-parse", "--abbrev-ref", "HEAD"])
            let status = runGit(["-C", repositoryRoot.path, "status", "--porcelain"]) ?? ""

            return TokenmonGitMetadata(
                branch: branch,
                commitShortHash: commit,
                hasLocalModifications: status.isEmpty == false
            )
        }

        return nil
    }

    private static func candidateDirectories(
        fileManager: FileManager,
        bundle: Bundle
    ) -> [URL] {
        var urls: [URL] = [URL(fileURLWithPath: fileManager.currentDirectoryPath)]

        if let executableURL = bundle.executableURL {
            var candidate = executableURL.deletingLastPathComponent()
            for _ in 0..<8 {
                urls.append(candidate)
                candidate.deleteLastPathComponent()
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    private static func repositoryRoot(containing candidate: URL) -> URL? {
        var current = candidate
        let fm = FileManager.default

        for _ in 0..<10 {
            let gitPath = current.appendingPathComponent(".git").path
            if fm.fileExists(atPath: gitPath) {
                return current
            }
            current.deleteLastPathComponent()
        }

        return nil
    }

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments

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

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              output.isEmpty == false else {
            return nil
        }

        return output
    }
}
