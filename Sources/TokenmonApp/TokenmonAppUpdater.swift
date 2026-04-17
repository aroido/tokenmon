import Foundation
import Sparkle
import TokenmonPersistence

enum TokenmonAppUpdaterConfigurationSource: String, Equatable, Sendable {
    case bundleMetadata = "bundle_metadata"
    case localOverrideFile = "local_override_file"
    case processEnvironment = "process_environment"

    var localizationKey: StaticString {
        switch self {
        case .bundleMetadata:
            return "settings.updates.source.bundle_metadata"
        case .localOverrideFile:
            return "settings.updates.source.local_override_file"
        case .processEnvironment:
            return "settings.updates.source.process_environment"
        }
    }

    var developerDescription: String {
        rawValue
    }
}

struct TokenmonAppUpdaterOverride: Codable, Equatable, Sendable {
    var feedURL: String?
    var publicEDKey: String?
}

enum TokenmonAppUpdaterOverrideStore {
    private static let fileName = "sparkle-updater-override.json"

    static func fileURL(databasePath: String? = nil) -> URL {
        URL(
            fileURLWithPath: TokenmonDatabaseManager.supportDirectory(forDatabasePath: databasePath),
            isDirectory: true
        )
        .appendingPathComponent(fileName)
    }

    static func filePath(databasePath: String? = nil) -> String {
        fileURL(databasePath: databasePath).path
    }

    static func load(
        databasePath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> TokenmonAppUpdaterOverride? {
        let fileURL = fileURL(databasePath: databasePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(TokenmonAppUpdaterOverride.self, from: data)
    }

    @discardableResult
    static func save(
        _ overrideConfiguration: TokenmonAppUpdaterOverride,
        databasePath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        let fileURL = fileURL(databasePath: databasePath)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(overrideConfiguration)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    static func clear(
        databasePath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let fileURL = fileURL(databasePath: databasePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        try fileManager.removeItem(at: fileURL)
        return true
    }
}

private struct TokenmonAppUpdaterConfigurationResolution: Equatable, Sendable {
    let feedURLString: String?
    let feedURLSource: TokenmonAppUpdaterConfigurationSource?
    let publicEDKey: String?
    let publicEDKeySource: TokenmonAppUpdaterConfigurationSource?
    let overrideFilePath: String
    let overrideFileExists: Bool
    let overrideLoadErrorDescription: String?

    static func resolve(
        infoDictionary: [String: Any],
        databasePath: String? = nil,
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> TokenmonAppUpdaterConfigurationResolution {
        let overrideFilePath = TokenmonAppUpdaterOverrideStore.filePath(databasePath: databasePath)
        let overrideFileExists = fileManager.fileExists(atPath: overrideFilePath)

        var feedURLString = stringValue(for: "SUFeedURL", in: infoDictionary)
        var feedURLSource: TokenmonAppUpdaterConfigurationSource? = feedURLString == nil ? nil : .bundleMetadata
        var publicEDKey = stringValue(for: "SUPublicEDKey", in: infoDictionary)
        var publicEDKeySource: TokenmonAppUpdaterConfigurationSource? = publicEDKey == nil ? nil : .bundleMetadata
        var overrideLoadErrorDescription: String?

        if overrideFileExists {
            do {
                if let overrideConfiguration = try TokenmonAppUpdaterOverrideStore.load(
                    databasePath: databasePath,
                    fileManager: fileManager
                ) {
                    if let overrideFeedURL = normalize(overrideConfiguration.feedURL) {
                        feedURLString = overrideFeedURL
                        feedURLSource = .localOverrideFile
                    }
                    if let overridePublicEDKey = normalize(overrideConfiguration.publicEDKey) {
                        publicEDKey = overridePublicEDKey
                        publicEDKeySource = .localOverrideFile
                    }
                }
            } catch {
                overrideLoadErrorDescription = error.localizedDescription
            }
        }

        if let environmentFeedURL = normalize(processInfo.environment["TOKENMON_SPARKLE_FEED_URL"]) {
            feedURLString = environmentFeedURL
            feedURLSource = .processEnvironment
        }

        let environmentPublicEDKey = normalize(processInfo.environment["TOKENMON_SPARKLE_PUBLIC_ED_KEY"])
            ?? normalize(processInfo.environment["SPARKLE_PUBLIC_ED_KEY"])
        if let environmentPublicEDKey {
            publicEDKey = environmentPublicEDKey
            publicEDKeySource = .processEnvironment
        }

        return TokenmonAppUpdaterConfigurationResolution(
            feedURLString: feedURLString,
            feedURLSource: feedURLSource,
            publicEDKey: publicEDKey,
            publicEDKeySource: publicEDKeySource,
            overrideFilePath: overrideFilePath,
            overrideFileExists: overrideFileExists,
            overrideLoadErrorDescription: overrideLoadErrorDescription
        )
    }

    var availability: TokenmonAppUpdaterAvailability.State {
        if overrideLoadErrorDescription != nil {
            return .unavailable(.invalidOverrideFile)
        }

        var infoDictionary: [String: Any] = [:]
        if let feedURLString {
            infoDictionary["SUFeedURL"] = feedURLString
        }
        if let publicEDKey {
            infoDictionary["SUPublicEDKey"] = publicEDKey
        }
        return TokenmonAppUpdaterAvailability.Configuration.resolve(infoDictionary: infoDictionary)
    }

    private static func stringValue(for key: String, in infoDictionary: [String: Any]) -> String? {
        normalize(infoDictionary[key] as? String)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct TokenmonAppUpdaterDiagnosticsSnapshot: Equatable, Sendable {
    let availability: TokenmonAppUpdaterAvailability.State
    let configuredFeedURL: URL?
    let feedURLSource: TokenmonAppUpdaterConfigurationSource?
    let publicEDKeySource: TokenmonAppUpdaterConfigurationSource?
    let overrideFilePath: String
    let overrideFileExists: Bool
    let overrideLoadErrorDescription: String?

    static func resolve(
        bundle: Bundle = .main,
        databasePath: String? = nil,
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> TokenmonAppUpdaterDiagnosticsSnapshot {
        resolve(
            infoDictionary: bundle.infoDictionary ?? [:],
            databasePath: databasePath,
            processInfo: processInfo,
            fileManager: fileManager
        )
    }

    static func resolve(
        infoDictionary: [String: Any],
        databasePath: String? = nil,
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> TokenmonAppUpdaterDiagnosticsSnapshot {
        let resolution = TokenmonAppUpdaterConfigurationResolution.resolve(
            infoDictionary: infoDictionary,
            databasePath: databasePath,
            processInfo: processInfo,
            fileManager: fileManager
        )

        return TokenmonAppUpdaterDiagnosticsSnapshot(
            availability: resolution.availability,
            configuredFeedURL: resolution.feedURLString.flatMap(URL.init(string:)),
            feedURLSource: resolution.feedURLSource,
            publicEDKeySource: resolution.publicEDKeySource,
            overrideFilePath: resolution.overrideFilePath,
            overrideFileExists: resolution.overrideFileExists,
            overrideLoadErrorDescription: resolution.overrideLoadErrorDescription
        )
    }

    var isAvailable: Bool {
        if case .available = availability {
            return true
        }
        return false
    }

    var unavailabilityReason: TokenmonAppUpdaterAvailability.Reason? {
        guard case .unavailable(let reason) = availability else {
            return nil
        }
        return reason
    }

    var feedURL: URL? {
        guard case .available(let configuration) = availability else {
            return nil
        }
        return configuration.feedURL
    }

    var hasNonBundledConfiguration: Bool {
        [feedURLSource, publicEDKeySource].contains { source in
            source != nil && source != .bundleMetadata
        }
    }
}

struct TokenmonAppUpdaterAvailability: Equatable {
    enum State: Equatable {
        case available(Configuration)
        case unavailable(Reason)
    }

    enum Reason: Equatable {
        case missingFeedURL
        case invalidFeedURL
        case missingPublicKey
        case invalidOverrideFile

        var localizationKey: StaticString {
            switch self {
            case .missingFeedURL:
                return "settings.updates.unavailable.missing_feed"
            case .invalidFeedURL:
                return "settings.updates.unavailable.invalid_feed"
            case .missingPublicKey:
                return "settings.updates.unavailable.missing_public_key"
            case .invalidOverrideFile:
                return "settings.updates.unavailable.invalid_override_file"
            }
        }
    }

    struct Configuration: Equatable {
        let feedURL: URL
        let publicEDKey: String

        static func resolve(infoDictionary: [String: Any]) -> State {
            guard let rawFeedURL = stringValue(for: "SUFeedURL", in: infoDictionary) else {
                return .unavailable(.missingFeedURL)
            }
            guard let feedURL = validatedFeedURL(rawFeedURL) else {
                return .unavailable(.invalidFeedURL)
            }
            guard let publicEDKey = stringValue(for: "SUPublicEDKey", in: infoDictionary) else {
                return .unavailable(.missingPublicKey)
            }
            return .available(
                Configuration(
                    feedURL: feedURL,
                    publicEDKey: publicEDKey
                )
            )
        }

        static func resolve(bundle: Bundle = .main) -> State {
            resolve(infoDictionary: bundle.infoDictionary ?? [:])
        }

        private static func stringValue(for key: String, in infoDictionary: [String: Any]) -> String? {
            guard let rawValue = infoDictionary[key] as? String else {
                return nil
            }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func validatedFeedURL(_ rawFeedURL: String) -> URL? {
            guard let feedURL = URL(string: rawFeedURL) else {
                return nil
            }

            if feedURL.isFileURL {
                return feedURL
            }

            guard let scheme = feedURL.scheme?.trimmingCharacters(in: .whitespacesAndNewlines),
                  scheme.isEmpty == false,
                  let host = feedURL.host?.trimmingCharacters(in: .whitespacesAndNewlines),
                  host.isEmpty == false
            else {
                return nil
            }

            return feedURL
        }
    }
}

@MainActor
final class TokenmonAppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    let diagnosticsSnapshot: TokenmonAppUpdaterDiagnosticsSnapshot
    let availability: TokenmonAppUpdaterAvailability.State

    private let analyticsBridge: TokenmonAppUpdaterAnalyticsBridge
    private let notificationBridge: TokenmonAppUpdateNotificationBridge
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    init(
        settingsProvider: @escaping @MainActor () -> AppSettings = { AppSettings() },
        notificationCoordinator: TokenmonCaptureNotificationCoordinating = TokenmonNoopCaptureNotificationCoordinator(),
        analyticsTracker: TokenmonAnalyticsTracking = TokenmonNoopAnalyticsTracker()
    ) {
        let diagnosticsSnapshot = TokenmonAppUpdaterDiagnosticsSnapshot.resolve()
        self.diagnosticsSnapshot = diagnosticsSnapshot
        availability = diagnosticsSnapshot.availability
        analyticsBridge = TokenmonAppUpdaterAnalyticsBridge(
            analyticsTracker: analyticsTracker,
            feedSourceProvider: {
                diagnosticsSnapshot.feedURLSource?.developerDescription
            }
        )
        notificationBridge = TokenmonAppUpdateNotificationBridge(
            settingsProvider: settingsProvider,
            notificationCoordinator: notificationCoordinator
        )

        super.init()

        switch availability {
        case .available:
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        case .unavailable:
            updaterController = nil
        }

        if let updater = updaterController?.updater {
            canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] observedUpdater, _ in
                Task { @MainActor [weak self] in
                    self?.canCheckForUpdates = observedUpdater.canCheckForUpdates
                }
            }
        }
    }

    deinit {
        canCheckObservation?.invalidate()
    }

    var isAvailable: Bool {
        diagnosticsSnapshot.isAvailable
    }

    var feedURL: URL? {
        diagnosticsSnapshot.feedURL
    }

    var configuredFeedURL: URL? {
        diagnosticsSnapshot.configuredFeedURL
    }

    var feedURLSource: TokenmonAppUpdaterConfigurationSource? {
        diagnosticsSnapshot.feedURLSource
    }

    var publicEDKeySource: TokenmonAppUpdaterConfigurationSource? {
        diagnosticsSnapshot.publicEDKeySource
    }

    var overrideFilePath: String {
        diagnosticsSnapshot.overrideFilePath
    }

    var overrideFileExists: Bool {
        diagnosticsSnapshot.overrideFileExists
    }

    var overrideLoadErrorDescription: String? {
        diagnosticsSnapshot.overrideLoadErrorDescription
    }

    var hasNonBundledConfiguration: Bool {
        diagnosticsSnapshot.hasNonBundledConfiguration
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController?.updater.automaticallyChecksForUpdates ?? false
    }

    var automaticallyDownloadsUpdates: Bool {
        updaterController?.updater.automaticallyDownloadsUpdates ?? false
    }

    var unavailabilityReasonKey: StaticString? {
        guard case .unavailable(let reason) = availability else {
            return nil
        }
        return reason.localizationKey
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ newValue: Bool) {
        guard let updater = updaterController?.updater else {
            return
        }

        updater.automaticallyChecksForUpdates = newValue
        if newValue == false && updater.automaticallyDownloadsUpdates {
            updater.automaticallyDownloadsUpdates = false
        }
        objectWillChange.send()
    }

    func setAutomaticallyDownloadsUpdates(_ newValue: Bool) {
        guard let updater = updaterController?.updater else {
            return
        }

        updater.automaticallyDownloadsUpdates = newValue
        objectWillChange.send()
    }
}

@MainActor
final class TokenmonAppUpdaterAnalyticsBridge {
    private let analyticsTracker: TokenmonAnalyticsTracking
    private let feedSourceProvider: () -> String?
    private var manualUpdateCheckInProgress = false

    init(
        analyticsTracker: TokenmonAnalyticsTracking,
        feedSourceProvider: @escaping () -> String?
    ) {
        self.analyticsTracker = analyticsTracker
        self.feedSourceProvider = feedSourceProvider
    }

    func beginUpdateCheck(_ updateCheck: SPUUpdateCheck) {
        let manualTriggered = updateCheck == .updates
        manualUpdateCheckInProgress = manualTriggered
        captureCheckRequested(manualTriggered: manualTriggered)
    }

    func setManualUpdateCheckInProgress(_ manual: Bool) {
        manualUpdateCheckInProgress = manual
    }

    func captureCheckRequested(manualTriggered: Bool) {
        analyticsTracker.captureUpdateStateChanged(
            stage: .checkRequested,
            availableVersion: nil,
            feedSource: feedSourceProvider(),
            manualTriggered: manualTriggered
        )
    }

    func captureUpdateAvailable(version: String?) {
        analyticsTracker.captureUpdateStateChanged(
            stage: .available,
            availableVersion: version,
            feedSource: feedSourceProvider(),
            manualTriggered: manualUpdateCheckInProgress
        )
    }

    func captureNoUpdateFound() {
        analyticsTracker.captureUpdateStateChanged(
            stage: .notAvailable,
            availableVersion: nil,
            feedSource: feedSourceProvider(),
            manualTriggered: manualUpdateCheckInProgress
        )
    }

    func captureDownloadCompleted(version: String?) {
        analyticsTracker.captureUpdateStateChanged(
            stage: .downloaded,
            availableVersion: version,
            feedSource: feedSourceProvider(),
            manualTriggered: manualUpdateCheckInProgress
        )
    }

    func captureDownloadFailed(version: String?) {
        analyticsTracker.captureUpdateStateChanged(
            stage: .downloadFailed,
            availableVersion: version,
            feedSource: feedSourceProvider(),
            manualTriggered: manualUpdateCheckInProgress
        )
    }

    func captureInstallRequested(version: String?) {
        analyticsTracker.captureUpdateStateChanged(
            stage: .installRequested,
            availableVersion: version,
            feedSource: feedSourceProvider(),
            manualTriggered: manualUpdateCheckInProgress
        )
    }
}

@MainActor
final class TokenmonAppUpdateNotificationBridge {
    private let settingsProvider: () -> AppSettings
    private let notificationCoordinator: TokenmonCaptureNotificationCoordinating
    private var automaticUpdateCheckInProgress = false
    private var lastNotifiedVersion: String?

    init(
        settingsProvider: @escaping () -> AppSettings,
        notificationCoordinator: TokenmonCaptureNotificationCoordinating
    ) {
        self.settingsProvider = settingsProvider
        self.notificationCoordinator = notificationCoordinator
    }

    func beginUpdateCheck(_ updateCheck: SPUUpdateCheck) {
        automaticUpdateCheckInProgress = updateCheck != .updates
    }

    func handleUpdateAvailable(version: String?) {
        guard automaticUpdateCheckInProgress else {
            return
        }

        let settings = settingsProvider()
        guard settings.updateNotificationsEnabled else {
            return
        }

        guard let version, version.isEmpty == false else {
            return
        }

        guard lastNotifiedVersion != version else {
            return
        }

        notificationCoordinator.sendUpdateAvailableNotification(version: version) { [weak self] scheduled in
            guard scheduled else {
                return
            }

            self?.lastNotifiedVersion = version
        }
    }

    func finishUpdateCheck() {
        automaticUpdateCheckInProgress = false
    }
}

extension TokenmonAppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerformUpdateCheck updateCheck: SPUUpdateCheck, error: AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool {
        _ = updater
        _ = error
        analyticsBridge.beginUpdateCheck(updateCheck)
        notificationBridge.beginUpdateCheck(updateCheck)
        return true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        _ = updater
        analyticsBridge.captureUpdateAvailable(version: item.displayVersionString)
        notificationBridge.handleUpdateAvailable(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        _ = updater
        analyticsBridge.captureNoUpdateFound()
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        _ = updater
        analyticsBridge.captureDownloadCompleted(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        _ = updater
        _ = error
        analyticsBridge.captureDownloadFailed(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        _ = updater
        analyticsBridge.captureInstallRequested(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        _ = updater
        _ = error
        analyticsBridge.setManualUpdateCheckInProgress(false)
        notificationBridge.finishUpdateCheck()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        _ = updater
        _ = updateCheck
        _ = error
        analyticsBridge.setManualUpdateCheckInProgress(false)
        notificationBridge.finishUpdateCheck()
    }
}
