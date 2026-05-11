import Darwin
import Foundation
import ServiceManagement
import SwiftUI
import TokenmonDomain
import TokenmonOtelProviders
import TokenmonPersistence
import TokenmonProviders

struct TokenmonDexNavigationRequest: Equatable {
    let requestID: UUID
    let speciesID: String

    init(speciesID: String) {
        requestID = UUID()
        self.speciesID = speciesID
    }
}

enum TokenmonNowCampCareActionResult: Equatable {
    case applied(NowCampCareResult)
    case failed(String)
}

enum TokenmonNowCampTrainActionResult: Equatable {
    case resolved(NowCampTrainingAttemptResult)
    case failed(String)
}

@MainActor
final class TokenmonMenuModel: ObservableObject {
    private static let inboxRefreshDebounceNanoseconds: UInt64 = 150_000_000
    private static let liveActivityPulseDuration: TimeInterval = 2.5

    @Published private(set) var runtimeSnapshot = TokenmonRuntimeSnapshot()
    @Published private(set) var insightsSnapshot = TokenmonInsightsSnapshot()
    @Published private(set) var diagnosticsSnapshot = TokenmonDiagnosticsSnapshot()
    @Published private(set) var liveActivityUntil: Date?
    @Published var selectedSettingsPane: TokenmonSettingsPane = .general
    @Published private(set) var dexNavigationRequest: TokenmonDexNavigationRequest?
    @Published private(set) var settingsMessage: String?
    @Published private(set) var settingsError: String?
    @Published private(set) var loadError: String?
    @Published private(set) var displayedSceneContext: TokenmonSceneContext?
    @Published private(set) var notificationAuthorizationState: TokenmonNotificationAuthorizationState = .unknown
    @Published private(set) var geminiReceiverState: GeminiOtelReceiverSupervisor.State = .stopped

    private let databasePath: String
    private let databaseManager: TokenmonDatabaseManager
    private let inboxMonitor: TokenmonInboxMonitor
    private let executablePath: String
    private let providerInspector: TokenmonProviderInspector
    private let launchAtLoginStateProvider: @Sendable () -> TokenmonLaunchAtLoginState
    private let loginItemsSettingsOpener: @Sendable () -> Void
    private let notificationSettingsOpener: @Sendable () -> TokenmonNotificationSettingsOpenResult
    private let notificationCoordinator: TokenmonCaptureNotificationCoordinating
    private let analyticsTracker: TokenmonAnalyticsTracking
    private var refreshTask: Task<Void, Never>?
    private var delayedInboxRefreshTask: Task<Void, Never>?
    private var careUptimeTask: Task<Void, Never>?
    private var refreshInFlight = false
    private var pendingRefreshScopes: TokenmonRefreshScopes = []
    private var pendingRefreshReasonLabels = Set<String>()
    private var liveMonitoringActive = false
    private var liveActivityPulseClearTask: Task<Void, Never>?
    private var pendingMenuBarEncounterAnimations: [RecentEncounterSummary] = []
    private var appOpenedAnalyticsEmitted = false

    init(
        databasePath: String = TokenmonDatabaseManager.defaultPath(),
        providerInspector: @escaping TokenmonProviderInspector = TokenmonProviderOnboarding.inspectAll,
        launchAtLoginStateProvider: @escaping @Sendable () -> TokenmonLaunchAtLoginState = TokenmonLaunchAtLoginController.snapshot,
        loginItemsSettingsOpener: @escaping @Sendable () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        },
        notificationSettingsOpener: @escaping @Sendable () -> TokenmonNotificationSettingsOpenResult = {
            TokenmonSystemSettingsOpener.openNotificationSettings()
        },
        notificationCoordinator: TokenmonCaptureNotificationCoordinating = TokenmonNoopCaptureNotificationCoordinator(),
        analyticsTracker: TokenmonAnalyticsTracking = TokenmonNoopAnalyticsTracker()
    ) {
        self.databasePath = databasePath
        executablePath = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        databaseManager = TokenmonDatabaseManager(path: databasePath)
        inboxMonitor = TokenmonInboxMonitor(databasePath: databasePath)
        self.providerInspector = providerInspector
        self.launchAtLoginStateProvider = launchAtLoginStateProvider
        self.loginItemsSettingsOpener = loginItemsSettingsOpener
        self.notificationSettingsOpener = notificationSettingsOpener
        self.notificationCoordinator = notificationCoordinator
        self.analyticsTracker = analyticsTracker
        if let storedSettings = try? databaseManager.appSettings() {
            diagnosticsSnapshot.appSettings = storedSettings
            TokenmonL10n.setLocaleOverride(storedSettings.languagePreference.localeIdentifier)
        }
        analyticsTracker.syncConsent(
            appSettings: diagnosticsSnapshot.appSettings,
            localeIdentifier: TokenmonL10n.activeLocale.identifier
        )
        logInfo(
            category: "localization",
            event: "localization_state_initialized",
            metadata: TokenmonL10n.diagnosticSnapshot()
        )
        logInfo(
            category: "app",
            event: "menu_model_initialized",
            metadata: ["database_path": databasePath]
        )
        TokenmonLaunchAtLoginController.cleanupLegacyFallbackIfNeeded()
        refreshNotificationAuthorizationState()
        refresh(reason: .initial)
        startNowCampCareUptimeTicker()
    }

    deinit {
        careUptimeTask?.cancel()
    }

    func activateLiveMonitoring() {
        guard liveMonitoringActive == false else {
            return
        }
        liveMonitoringActive = true
        inboxMonitor.performInitialScanAsync { [weak self] in
            self?.refresh(reason: .inboxEvent)
        }
        inboxMonitor.startAsync { [weak self] in
            self?.refresh(reason: .inboxEvent)
        }
    }

    private func startNowCampCareUptimeTicker() {
        careUptimeTask?.cancel()
        careUptimeTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard Task.isCancelled == false else {
                    return
                }
                self?.advanceNowCampCareUptimeTick()
            }
        }
    }

    private func advanceNowCampCareUptimeTick() {
        do {
            let result = try databaseManager.advanceNowCampCareUptime(seconds: 60)
            guard result.didChange else {
                return
            }
            refresh(reason: .partyChanged)
        } catch {
            logError(
                category: "now_camp",
                event: "care_uptime_tick_failed",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func refresh(reason: TokenmonRefreshReason = .manual) {
        let scopes = reason.resolvedScopes(insightsLoaded: insightsSnapshot.isLoaded)
        logDebug(
            category: "refresh",
            event: "refresh_requested",
            metadata: [
                "reason": String(describing: reason),
                "scopes": scopes.logLabel,
            ]
        )
        let reasonLabel = String(describing: reason)

        if case .inboxEvent = reason {
            delayedInboxRefreshTask?.cancel()
            delayedInboxRefreshTask = Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: Self.inboxRefreshDebounceNanoseconds)
                } catch {
                    return
                }

                guard Task.isCancelled == false else {
                    return
                }

                delayedInboxRefreshTask = nil
                let scopes = reason.resolvedScopes(insightsLoaded: self.insightsSnapshot.isLoaded)
                enqueueRefresh(scopes: scopes, reasonLabels: [reasonLabel])
            }
            return
        }

        delayedInboxRefreshTask?.cancel()
        delayedInboxRefreshTask = nil
        enqueueRefresh(scopes: scopes, reasonLabels: [reasonLabel])
    }

    func surfaceOpened(
        _ surface: TokenmonRefreshSurface,
        entrypoint: String = "surface",
        refresh shouldRefresh: Bool = true,
        emitAnalytics: Bool = true
    ) {
        if emitAnalytics {
            analyticsTracker.captureSurfaceOpened(
                surface: surface,
                entrypoint: entrypoint,
                settingsPane: surface == .settings ? selectedSettingsPane : nil
            )
        }
        if case .settings = surface {
            TokenmonLaunchAtLoginController.cleanupLegacyFallbackIfNeeded()
            refreshNotificationAuthorizationState()
        }
        if shouldRefresh {
            self.refresh(reason: .surfaceOpened(surface))
        }
    }

    func waitForRefreshToFinish() async {
        while refreshInFlight || pendingRefreshScopes.isEmpty == false || delayedInboxRefreshTask != nil {
            if let refreshTask {
                await refreshTask.value
            } else if let delayedInboxRefreshTask {
                await delayedInboxRefreshTask.value
            } else {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    func recordLiveActivityPulse() {
        let now = Date()
        let expiration = now.addingTimeInterval(Self.liveActivityPulseDuration)
        if let current = liveActivityUntil, current > expiration {
            return
        }

        liveActivityUntil = expiration
        liveActivityPulseClearTask?.cancel()
        liveActivityPulseClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.liveActivityPulseDuration * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }
                if let activeUntil = self.liveActivityUntil, activeUntil <= Date() {
                    self.liveActivityUntil = nil
                }
            }
        }
    }

    private func enqueueRefresh(scopes: TokenmonRefreshScopes, reasonLabels: Set<String>) {
        if refreshInFlight {
            pendingRefreshScopes.formUnion(scopes)
            pendingRefreshReasonLabels.formUnion(reasonLabels)
            logDebug(
                category: "refresh",
                event: "refresh_coalesced",
                metadata: [
                    "queued_scopes": pendingRefreshScopes.logLabel,
                    "queued_reasons": pendingRefreshReasonLabels.sorted().joined(separator: ","),
                ]
            )
            return
        }

        startRefresh(scopes: scopes, reasonLabels: reasonLabels)
    }

    private func startRefresh(scopes: TokenmonRefreshScopes, reasonLabels: Set<String>) {
        let refreshStartedAt = Date()
        let databasePath = databasePath
        let executablePath = executablePath
        let providerInspector = providerInspector
        let launchAtLoginState = scopes.contains(.diagnostics) ? launchAtLoginStateProvider() : nil
        let reasonLabel = reasonLabels.sorted().joined(separator: ",")

        refreshInFlight = true
        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await TokenmonMenuSnapshotLoader.load(
                    databasePath: databasePath,
                    executablePath: executablePath,
                    scopes: scopes,
                    providerInspector: providerInspector,
                    launchAtLoginState: launchAtLoginState
                )
                guard Task.isCancelled == false else {
                    return
                }
                applyRefreshResult(result)
                loadError = nil
                logDebug(
                    category: "refresh",
                    event: "refresh_completed",
                    metadata: [
                        "reason": reasonLabel,
                        "scopes": scopes.logLabel,
                        "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: refreshStartedAt),
                        "runtime_loaded": result.runtime != nil ? "yes" : "no",
                        "insights_loaded": result.insights != nil ? "yes" : "no",
                        "diagnostics_loaded": result.diagnostics != nil ? "yes" : "no",
                    ]
                )
            } catch is CancellationError {
                return
            } catch {
                logError(
                    category: "refresh",
                    event: "refresh_failed",
                    metadata: [
                        "reason": reasonLabel,
                        "scopes": scopes.logLabel,
                        "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: refreshStartedAt),
                        "error": error.localizedDescription,
                    ]
                )
                loadError = error.localizedDescription
            }

            refreshInFlight = false
            refreshTask = nil

            if pendingRefreshScopes.isEmpty == false {
                let nextScopes = pendingRefreshScopes
                let nextReasonLabels = pendingRefreshReasonLabels
                pendingRefreshScopes = []
                pendingRefreshReasonLabels.removeAll()
                startRefresh(scopes: nextScopes, reasonLabels: nextReasonLabels)
            }
        }
    }

    private func applyRefreshResult(_ result: TokenmonMenuRefreshResult) {
        let previousProviderHealth = providerHealthByProvider
        let canEmitTransitionAnalytics = runtimeSnapshot.isLoaded || diagnosticsSnapshot.isLoaded

        if let runtime = result.runtime, runtime != runtimeSnapshot {
            let previousRuntime = runtimeSnapshot
            let newEncounterAnimations = TokenmonEncounterDeltaResolver.newEncounters(
                previous: previousRuntime,
                current: runtime
            )
            runtimeSnapshot = runtime
            enqueueMenuBarEncounterAnimations(newEncounterAnimations)
            notificationCoordinator.runtimeDidRefresh(
                from: previousRuntime,
                to: runtime,
                settings: appSettings
            )
            for encounter in newEncounterAnimations {
                analyticsTracker.captureEncounterResolved(
                    encounter: encounter,
                    isFirstSeen: encounter.seenCount == 1,
                    isFirstCapture: encounter.outcome == .captured && encounter.capturedCount == 1
                )
            }
        }
        if let insights = result.insights, insights != insightsSnapshot {
            insightsSnapshot = insights
        }
        if let diagnostics = result.diagnostics, diagnostics != diagnosticsSnapshot {
            TokenmonL10n.setLocaleOverride(diagnostics.appSettings.languagePreference.localeIdentifier)
            TokenmonAppAppearanceController.apply(diagnostics.appSettings.appearancePreference)
            diagnosticsSnapshot = diagnostics
        }

        guard canEmitTransitionAnalytics else {
            return
        }

        for (provider, currentSummary) in providerHealthByProvider {
            let previousSummary = previousProviderHealth[provider]
            guard providerHealthChanged(previous: previousSummary, current: currentSummary) else {
                continue
            }

            analyticsTracker.captureProviderHealthChanged(
                provider: provider,
                previousHealthState: previousSummary?.healthState ?? "unknown",
                sourceMode: currentSummary.sourceMode,
                healthState: currentSummary.healthState,
                liveGameplayArmed: currentSummary.liveGameplayArmed
            )
        }
    }

    func observeGeminiReceiver(_ supervisor: GeminiOtelReceiverSupervisor) {
        Task { @MainActor [weak self] in
            for await newValue in supervisor.$state.values {
                self?.geminiReceiverState = newValue
            }
        }
    }

    func updateNotificationsEnabled(_ value: Bool) {
        logInfo(
            category: "settings",
            event: "notifications_preference_changed",
            metadata: ["enabled": String(value)]
        )
        var settings = appSettings
        settings.notificationsEnabled = value
        guard persist(settings: settings) else {
            return
        }
        runNotificationPreferenceFlow(isEnabled: value)
    }

    func updateUpdateNotificationsEnabled(_ value: Bool) {
        logInfo(
            category: "settings",
            event: "update_notifications_preference_changed",
            metadata: ["enabled": String(value)]
        )
        var settings = appSettings
        settings.updateNotificationsEnabled = value
        guard persist(settings: settings) else {
            return
        }
        runUpdateNotificationPreferenceFlow(isEnabled: value)
    }

    func updateUsageAnalyticsEnabled(_ value: Bool) {
        let wasEnabled = appSettings.usageAnalyticsEnabled
        var settings = appSettings
        settings.usageAnalyticsEnabled = value
        if value {
            settings.usageAnalyticsPromptDismissed = true
        }
        guard persist(settings: settings) else {
            return
        }

        if value && !wasEnabled {
            emitAppOpenedAnalyticsIfNeeded()
        }
    }

    func dismissUsageAnalyticsPrompt() {
        guard appSettings.usageAnalyticsPromptDismissed == false else {
            return
        }

        var settings = appSettings
        settings.usageAnalyticsPromptDismissed = true
        _ = persist(settings: settings)
    }

    func requestCaptureNotificationPermission() {
        runNotificationPreferenceFlow(isEnabled: true)
    }

    func markFirstRunOnboardingShown() {
        guard appSettings.firstRunSetupPromptShown == false else {
            return
        }

        var settings = appSettings
        settings.firstRunSetupPromptShown = true
        guard persist(settings: settings) else {
            return
        }

        logInfo(category: "settings", event: "first_run_onboarding_marked_shown")
    }

    func openSystemNotificationSettings() {
        switch notificationSettingsOpener() {
        case .openedAppSpecific:
            logInfo(category: "settings", event: "opened_system_notification_settings")
            settingsMessage = TokenmonL10n.string("settings.feedback.opened_notification_settings")
            settingsError = nil
        case .openedGenericNotifications:
            logInfo(category: "settings", event: "opened_generic_notification_settings")
            settingsMessage = TokenmonL10n.string("settings.feedback.opened_notification_settings_generic")
            settingsError = nil
        case .openedSystemSettingsRoot:
            logInfo(category: "settings", event: "opened_system_settings_root")
            settingsMessage = TokenmonL10n.string("settings.feedback.opened_system_settings")
            settingsError = nil
        case .failed:
            logError(category: "settings", event: "failed_to_open_system_notification_settings")
            settingsError = TokenmonL10n.string("settings.feedback.failed_notification_settings")
            settingsMessage = nil
        }
        refreshNotificationAuthorizationState()
    }

    func openLoginItemsSettings() {
        loginItemsSettingsOpener()
        logInfo(category: "settings", event: "opened_login_items_settings")
        settingsMessage = TokenmonL10n.string("settings.feedback.opened_login_items_settings")
        settingsError = nil
        updateDiagnosticsSnapshot { snapshot in
            snapshot.launchAtLoginState = TokenmonLaunchAtLoginController.snapshot()
        }
    }

    func updateProviderStatusVisibility(_ value: Bool) {
        var settings = appSettings
        settings.providerStatusVisibility = value
        persist(settings: settings)
    }

    func updateFieldBackplateEnabled(_ value: Bool) {
        var settings = appSettings
        settings.fieldBackplateEnabled = value
        persist(settings: settings)
    }

    func updateAppearancePreference(_ value: AppAppearancePreference) {
        var settings = appSettings
        settings.appearancePreference = value
        persist(settings: settings)
    }

    func updateLanguagePreference(_ value: AppLanguagePreference) {
        var settings = appSettings
        settings.languagePreference = value
        persist(settings: settings)
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            let updatedState = try TokenmonLaunchAtLoginController.setEnabled(value)
            guard updatedState.isSupported else {
                updateDiagnosticsSnapshot { snapshot in
                    snapshot.launchAtLoginState = updatedState
                }
                settingsError = updatedState.reason
                return
            }

            updateDiagnosticsSnapshot { snapshot in
                snapshot.launchAtLoginState = updatedState
            }
            settingsError = nil

            var settings = appSettings
            settings.launchAtLogin = updatedState.isEnabled
            persist(settings: settings)
        } catch {
            updateDiagnosticsSnapshot { snapshot in
                snapshot.launchAtLoginState = TokenmonLaunchAtLoginController.snapshot()
            }
            settingsError = error.localizedDescription
        }
    }

    func connectProvider(_ provider: ProviderCode) {
        logInfo(category: "providers", event: "connect_provider_requested", metadata: ["provider": provider.rawValue])
        if provider == .cursor {
            selectedSettingsPane = .providers
            syncCursorUsage()
            return
        }
        let onboardingStatus = providerInspector(databasePath, executablePath, providerInstallationPreferences)
            .first { $0.provider == provider }
        do {
            let result = try TokenmonProviderOnboarding.install(
                provider: provider,
                databasePath: databasePath,
                executablePath: executablePath,
                preferences: providerInstallationPreferences
            )
            selectedSettingsPane = .providers
            settingsMessage = result.message
            settingsError = nil
            analyticsTracker.captureProviderSetupResult(
                provider: provider,
                trigger: .manual,
                result: .completed,
                cliInstalled: onboardingStatus?.cliInstalled ?? false,
                isPartial: onboardingStatus?.isPartial ?? false
            )
            logNotice(category: "providers", event: "connect_provider_completed", metadata: ["provider": provider.rawValue])
            refresh(reason: .manual)
        } catch {
            selectedSettingsPane = .providers
            settingsError = error.localizedDescription
            settingsMessage = nil
            analyticsTracker.captureProviderSetupResult(
                provider: provider,
                trigger: .manual,
                result: .failed,
                cliInstalled: onboardingStatus?.cliInstalled ?? false,
                isPartial: onboardingStatus?.isPartial ?? false
            )
            logError(
                category: "providers",
                event: "connect_provider_failed",
                metadata: [
                    "provider": provider.rawValue,
                    "error": error.localizedDescription,
                ]
            )
            refresh(reason: .manual)
        }
    }

    func redetectProviders() {
        refresh(reason: .surfaceOpened(.settings))
        settingsMessage = TokenmonL10n.string("settings.feedback.redetected_providers")
        settingsError = nil
    }

    func presentSettingsFeedback(message: String?, error: String?) {
        settingsMessage = message
        settingsError = error
    }

    func setProviderExecutableOverride(_ path: String?, for provider: ProviderCode) {
        var preferences = providerInstallationPreferences
        preferences.setExecutablePath(path, for: provider)
        persist(providerInstallationPreferences: preferences)
    }

    func setProviderConfigurationOverride(_ path: String?, for provider: ProviderCode) {
        var preferences = providerInstallationPreferences
        preferences.setConfigurationPath(path, for: provider)
        persist(providerInstallationPreferences: preferences)
    }

    func resetProviderOverrides(for provider: ProviderCode) {
        var preferences = providerInstallationPreferences
        preferences.resetOverrides(for: provider)
        persist(providerInstallationPreferences: preferences)
    }

    func setCodexConnectionMode(_ mode: CodexConnectionMode) {
        var preferences = providerInstallationPreferences
        preferences.codexMode = mode
        persist(providerInstallationPreferences: preferences)
    }

    func revealSettingsPane(_ pane: TokenmonSettingsPane) {
        selectedSettingsPane = pane
    }

    func requestDexNavigation(to speciesID: String) {
        dexNavigationRequest = TokenmonDexNavigationRequest(speciesID: speciesID)
    }

    func clearDexNavigationRequest(_ request: TokenmonDexNavigationRequest) {
        guard dexNavigationRequest == request else {
            return
        }
        dexNavigationRequest = nil
    }

    func resetGameplayProgress() {
        do {
            try databaseManager.resetProgress()
            selectedSettingsPane = .general
            settingsMessage = TokenmonL10n.string("settings.feedback.reset_progress")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            selectedSettingsPane = .general
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func resetDexProgress() {
        do {
            try databaseManager.resetDexProgress()
            settingsMessage = TokenmonL10n.string("settings.feedback.reset_dex")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func resetEncounterHistory() {
        do {
            try databaseManager.resetEncounterHistory()
            settingsMessage = TokenmonL10n.string("settings.feedback.reset_encounters")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    @discardableResult
    func addSpeciesToParty(_ speciesID: String) -> PartyMutationOutcome {
        do {
            try databaseManager.addToParty(speciesID: speciesID)
            refresh(reason: .partyChanged)
            return .added
        } catch PartyStoreError.partyFull {
            return .partyFull
        } catch PartyStoreError.partyNotCapturedYet {
            return .notCaptured
        } catch {
            loadError = "\(error)"
            return .failed
        }
    }

    @discardableResult
    func removeSpeciesFromParty(_ speciesID: String) -> PartyMutationOutcome {
        do {
            try databaseManager.removeFromParty(speciesID: speciesID)
            refresh(reason: .partyChanged)
            return .removed
        } catch {
            loadError = "\(error)"
            return .failed
        }
    }

    func setNowCampLead(_ speciesID: String?) {
        do {
            try databaseManager.setNowCampLead(speciesID: speciesID)
            loadError = nil
            refresh(reason: .partyChanged)
        } catch {
            loadError = error.localizedDescription
            refresh(reason: .partyChanged)
        }
    }

    @discardableResult
    func applyNowCampCareToLead() -> TokenmonNowCampCareActionResult {
        do {
            let result = try databaseManager.applyLeadCare()
            loadError = nil
            refresh(reason: .partyChanged)
            return .applied(result)
        } catch {
            let message = localizedNowCampCareFailureMessage(for: error)
            loadError = message
            refresh(reason: .partyChanged)
            return .failed(message)
        }
    }

    private func localizedNowCampCareFailureMessage(for error: Error) -> String {
        guard let storeError = error as? NowCampStoreError else {
            return error.localizedDescription
        }

        switch storeError {
        case .missingLead:
            return TokenmonL10n.string("now.camp.action.missing_lead")
        case .careNotReady:
            return TokenmonL10n.string("now.camp.feedback.care_not_ready")
        case .focusFull:
            return TokenmonL10n.string("now.camp.feedback.care_focus_full")
        case .insufficientFocus(let required, let available):
            return TokenmonL10n.format(
                "now.camp.action.insufficient_care_focus",
                Int64(available),
                Int64(required)
            )
        case .rankAtAffinityGate(_, let rank, let affinityLevel):
            guard rank.next != nil else {
                return TokenmonL10n.string("now.camp.action.rank_max")
            }
            return TokenmonL10n.format(
                "now.camp.action.rank_gate",
                affinityLevel,
                Int64(min(5, rank.rawValue + 1))
            )
        case .leadNotInParty, .missingTraining:
            return storeError.localizedDescription
        }
    }

    @discardableResult
    func trainNowCampLead() -> TokenmonNowCampTrainActionResult {
        do {
            let result = try databaseManager.trainNowCampLead()
            loadError = nil
            refresh(reason: .partyChanged)
            return .resolved(result)
        } catch {
            let message = localizedNowCampTrainFailureMessage(for: error)
            loadError = message
            refresh(reason: .partyChanged)
            return .failed(message)
        }
    }

    private func localizedNowCampTrainFailureMessage(for error: Error) -> String {
        guard let storeError = error as? NowCampStoreError else {
            return error.localizedDescription
        }

        switch storeError {
        case .missingLead:
            return TokenmonL10n.string("now.camp.action.missing_lead")
        case .insufficientFocus(let required, let available):
            return TokenmonL10n.format(
                "now.camp.feedback.train_not_ready",
                Int64(available),
                Int64(required)
            )
        case .rankAtAffinityGate(_, let rank, let affinityLevel):
            guard rank.next != nil else {
                return TokenmonL10n.string("now.camp.action.rank_max")
            }
            return TokenmonL10n.format(
                "now.camp.feedback.train_bond_gate",
                affinityLevel,
                Int64(min(TrainingRank.rankV.rawValue, rank.rawValue + 1))
            )
        case .careNotReady:
            return TokenmonL10n.string("now.camp.feedback.care_not_ready")
        case .focusFull:
            return TokenmonL10n.string("now.camp.feedback.care_focus_full")
        case .leadNotInParty, .missingTraining:
            return storeError.localizedDescription
        }
    }

    enum PartyMutationOutcome {
        case added, removed, partyFull, notCaptured, failed
    }

    func makeNextEncounterReady() {
        do {
            try databaseManager.makeNextEncounterReady()
            settingsMessage = TokenmonL10n.string("settings.feedback.prime_next_encounter")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func applyExplorationOverride(
        totalNormalizedTokens: Int64,
        tokensSinceLastEncounter: Int64,
        nextEncounterThresholdTokens: Int64
    ) {
        do {
            try databaseManager.applyExplorationOverride(
                totalNormalizedTokens: totalNormalizedTokens,
                tokensSinceLastEncounter: tokensSinceLastEncounter,
                nextEncounterThresholdTokens: nextEncounterThresholdTokens
            )
            settingsMessage = TokenmonL10n.string("settings.feedback.exploration_override")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func applyTotalsOverride(totalEncounters: Int64, totalCaptures: Int64) {
        do {
            try databaseManager.applyTotalsOverride(
                totalEncounters: totalEncounters,
                totalCaptures: totalCaptures
            )
            settingsMessage = TokenmonL10n.string("settings.feedback.totals_override")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func forgeEncounter(
        provider: ProviderCode,
        field: FieldType,
        rarity: RarityTier,
        speciesID: String,
        outcome: EncounterOutcome
    ) {
        logInfo(
            category: "developer",
            event: "forge_encounter_requested",
            metadata: [
                "provider": provider.rawValue,
                "field": field.rawValue,
                "rarity": rarity.rawValue,
                "species_id": speciesID,
                "outcome": outcome.rawValue,
            ]
        )
        do {
            _ = try databaseManager.forgeEncounter(
                TokenmonDeveloperEncounterForgeRequest(
                    provider: provider,
                    field: field,
                    rarity: rarity,
                    speciesID: speciesID,
                    outcome: outcome
                )
            )
            settingsMessage = TokenmonL10n.format("settings.feedback.forged_encounter", rarity.displayName, field.displayName)
            settingsError = nil
            logNotice(category: "developer", event: "forge_encounter_completed", metadata: ["species_id": speciesID])
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            logError(
                category: "developer",
                event: "forge_encounter_failed",
                metadata: ["error": error.localizedDescription]
            )
            refresh(reason: .manual)
        }
    }

    func sendCaptureNotificationPreview(speciesID: String) {
        guard let species = SpeciesCatalog.all.first(where: { $0.id == speciesID }) else {
            settingsError = TokenmonL10n.format("settings.feedback.preview_alert_missing_species", speciesID)
            settingsMessage = nil
            return
        }
        logInfo(
            category: "notifications",
            event: "preview_capture_alert_requested",
            metadata: [
                "species_id": species.id,
                "asset_key": species.assetKey,
            ]
        )

        notificationCoordinator.sendPreviewCaptureNotification(
            speciesID: species.id,
            assetKey: species.assetKey,
            speciesName: species.name,
            subtitle: TokenmonL10n.format("capture.notification.subtitle", species.rarity.displayName, species.field.displayName)
        ) { [weak self] message, error in
            guard let self else {
                return
            }
            self.settingsMessage = message
            self.settingsError = error
            if let error {
                self.logError(
                    category: "notifications",
                    event: "preview_capture_alert_failed",
                    metadata: [
                        "species_id": species.id,
                        "error": error,
                    ]
                )
            } else {
                self.logNotice(
                    category: "notifications",
                    event: "preview_capture_alert_scheduled",
                    metadata: ["species_id": species.id]
                )
            }
        }
    }

    func runScenarioPreset(_ preset: TokenmonDeveloperScenarioPreset) {
        do {
            switch preset {
            case .encounterReady:
                try databaseManager.makeNextEncounterReady()
            case .starterShowcase:
                try databaseManager.resetEncounterHistory()
                try forgePresetEncounter(provider: .codex, field: .grassland, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .codex, field: .ice, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .claude, field: .coast, rarity: .uncommon, outcome: .captured)
                try forgePresetEncounter(provider: .claude, field: .sky, rarity: .rare, outcome: .escaped)
            case .rarityShowcase:
                try databaseManager.resetEncounterHistory()
                try forgePresetEncounter(provider: .codex, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .codex, rarity: .uncommon, outcome: .captured)
                try forgePresetEncounter(provider: .claude, rarity: .rare, outcome: .captured)
                try forgePresetEncounter(provider: .claude, rarity: .epic, outcome: .escaped)
                try forgePresetEncounter(provider: .claude, rarity: .legendary, outcome: .escaped)
            case .denseDexProgress:
                try databaseManager.resetEncounterHistory()
                try forgePresetEncounter(provider: .codex, field: .grassland, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .codex, field: .ice, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .codex, field: .coast, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .codex, field: .sky, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .claude, field: .coast, rarity: .rare, outcome: .captured)
                try forgePresetEncounter(provider: .claude, field: .sky, rarity: .epic, outcome: .captured)
            case .mixedOutcomes:
                try databaseManager.resetEncounterHistory()
                try forgePresetEncounter(provider: .codex, field: .grassland, rarity: .common, outcome: .captured)
                try forgePresetEncounter(provider: .codex, field: .coast, rarity: .rare, outcome: .escaped)
                try forgePresetEncounter(provider: .claude, field: .ice, rarity: .epic, outcome: .captured)
                try forgePresetEncounter(provider: .claude, field: .sky, rarity: .legendary, outcome: .escaped)
            }
            settingsMessage = preset.successMessage
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func bootstrapAppState() {
        do {
            try databaseManager.bootstrap()
            inboxMonitor.performInitialScan()
            settingsMessage = TokenmonL10n.string("settings.feedback.rerun_bootstrap")
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func reseedSpeciesCatalog() {
        do {
            let result = try SpeciesSeeder.seed(databasePath: databasePath)
            settingsMessage = TokenmonL10n.format("settings.feedback.reseed_species", result.totalSpecies, result.insertedSpecies)
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func rescanInbox() {
        inboxMonitor.performInitialScan()
        settingsMessage = TokenmonL10n.string("settings.feedback.rescan_inbox")
        settingsError = nil
        refresh(reason: .manual)
    }

    func performDatabaseMaintenance() {
        do {
            let result = try databaseManager.performMaintenance()
            settingsMessage = TokenmonL10n.format(
                "settings.feedback.database_maintenance",
                result.freelistPagesBefore - result.freelistPagesAfter,
                result.fileSizeBytesBefore,
                result.fileSizeBytesAfter
            )
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func syncCursorUsage() {
        Task { [weak self] in
            guard let self else {
                return
            }
            await performCursorUsageSync(.manual)
        }
    }

    func syncCursorUsageInBackground() async {
        await performCursorUsageSync(.background)
    }

    func runTranscriptBackfill(
        provider: ProviderCode,
        transcriptPath: String,
        sessionID: String?
    ) {
        let completedAt = ISO8601DateFormatter().string(from: Date())
        do {
            switch provider {
            case .claude:
                let result = try ClaudeTranscriptBackfillService.run(
                    databasePath: databasePath,
                    providerSessionID: sessionID?.nilIfEmpty,
                    transcriptPath: transcriptPath
                )
                analyticsTracker.captureBackfillRunCompleted(
                    BackfillRunSummary(
                        backfillRunID: result.backfillRunID,
                        provider: .claude,
                        mode: "transcript_backfill",
                        status: result.status,
                        startedAt: completedAt,
                        completedAt: completedAt,
                        samplesExamined: result.samplesExamined,
                        samplesCreated: result.samplesCreated,
                        duplicatesSkipped: result.duplicatesSkipped,
                        errorsCount: result.errorsCount,
                        summaryJSON: result.summaryJSON
                    )
                )
                settingsMessage = TokenmonL10n.format("settings.feedback.claude_backfill_complete", result.samplesCreated, result.duplicatesSkipped)
            case .codex:
                let result = try CodexTranscriptBackfillService.run(
                    databasePath: databasePath,
                    providerSessionID: sessionID?.nilIfEmpty,
                    transcriptPath: transcriptPath
                )
                if result.backfillRunID > 0 {
                    analyticsTracker.captureBackfillRunCompleted(
                        BackfillRunSummary(
                            backfillRunID: result.backfillRunID,
                            provider: .codex,
                            mode: "transcript_backfill",
                            status: result.status,
                            startedAt: completedAt,
                            completedAt: completedAt,
                            samplesExamined: result.samplesExamined,
                            samplesCreated: result.samplesCreated,
                            duplicatesSkipped: result.duplicatesSkipped,
                            errorsCount: result.errorsCount,
                            summaryJSON: result.summaryJSON
                        )
                    )
                }
                if result.status == "noop" {
                    settingsMessage = TokenmonL10n.string("settings.feedback.codex_backfill_noop")
                } else {
                    settingsMessage = TokenmonL10n.format("settings.feedback.codex_backfill_complete", result.samplesCreated, result.duplicatesSkipped)
                }
            case .gemini:
                settingsMessage = TokenmonL10n.string("settings.feedback.gemini_backfill_unsupported")
            case .cursor:
                settingsMessage = "Cursor transcript backfill is not supported"
            case .openclaw:
                settingsMessage = "OpenClaw transcript backfill is not supported"
            }
            settingsError = nil
            refresh(reason: .manual)
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            refresh(reason: .manual)
        }
    }

    func nextStep(for summary: ProviderHealthSummary) -> String {
        switch (summary.provider, summary.healthState) {
        case (.claude, "missing_configuration"):
            return TokenmonL10n.string("settings.providers.next_step.claude_missing_configuration")
        case (.codex, "missing_configuration"):
            return TokenmonL10n.string("settings.providers.next_step.codex_missing_configuration")
        case (.codex, "unsupported"):
            return TokenmonL10n.string("settings.providers.next_step.codex_unsupported")
        case (.gemini, "missing_configuration"):
            return TokenmonL10n.string("settings.providers.next_step.gemini_missing_configuration")
        case (.cursor, "missing_configuration"):
            return TokenmonL10n.string("settings.providers.next_step.cursor_missing_configuration")
        case (_, "experimental"):
            return TokenmonL10n.string("settings.providers.next_step.experimental")
        case (_, "degraded"):
            return TokenmonL10n.string("settings.providers.next_step.degraded")
        case (_, "unsupported"):
            return TokenmonL10n.string("settings.providers.next_step.unsupported")
        default:
            return TokenmonL10n.string("settings.providers.next_step.default")
        }
    }

    var currentDatabasePath: String { databasePath }

    var databaseSummary: TokenmonDatabaseSummary? { diagnosticsSnapshot.databaseSummary }

    var appUpdaterDiagnostics: TokenmonAppUpdaterDiagnosticsSnapshot { diagnosticsSnapshot.appUpdaterDiagnostics }

    var summary: CurrentRunSummary? { runtimeSnapshot.summary }

    var latestEncounter: RecentEncounterSummary? { runtimeSnapshot.latestEncounter }

    var recentEncounterFeed: [RecentEncounterSummary] { runtimeSnapshot.recentEncounterFeed }

    var raidDashboard: RaidDashboardSummary? { runtimeSnapshot.raidDashboard }

    var achievementBadges: [AchievementBadgeSummary] { runtimeSnapshot.achievementBadges }

    var nowCampSummary: NowCampSummary? { runtimeSnapshot.nowCampSummary }

    var dexEntries: [DexEntrySummary] { insightsSnapshot.dexEntries }

    var partyMembers: [PartyMemberSummary] { insightsSnapshot.partyMembers }
    var partySpeciesIDs: Set<String> { insightsSnapshot.partySpeciesIDs }
    var nowCampLeadSpeciesID: String? { nowCampSummary?.leadSpeciesID }
    var isPartyFull: Bool { partyMembers.count >= 10 }

    var todayActivity: TodayActivitySummary? { runtimeSnapshot.todayActivity }

    var fieldDistribution: [FieldType: Int] { insightsSnapshot.fieldDistribution }

    var dailyTrend: [DailyEncounterBucket] { insightsSnapshot.dailyTrend }

    var recentCaptures: [DexEntrySummary] { insightsSnapshot.recentCaptures }

    var tokenTotals: TokenUsageTotals? { insightsSnapshot.tokenTotals }

    var tokenUsageSourceSummary: TokenUsageSourceSummary { insightsSnapshot.tokenUsageSourceSummary }

    var tokenByProviderToday: [ProviderCode: Int64] { insightsSnapshot.tokenByProviderToday }

    var tokenHourlyRolling: [HourTokenBucket] { insightsSnapshot.tokenHourlyRolling }

    var recentSessions: [ProviderSessionTokens] { insightsSnapshot.recentSessions }

    var providerHealthSummaries: [ProviderHealthSummary] {
        diagnosticsSnapshot.providerHealthSummaries.isEmpty
            ? runtimeSnapshot.providerHealthSummaries
            : diagnosticsSnapshot.providerHealthSummaries
    }

    var recentDomainEventRecords: [PersistedDomainEventRecord] {
        insightsSnapshot.recentDomainEventRecords.isEmpty
            ? diagnosticsSnapshot.recentDomainEventRecords
            : insightsSnapshot.recentDomainEventRecords
    }

    var recentProviderSessionSummaries: [ProviderSessionSummary] {
        diagnosticsSnapshot.recentProviderSessionSummaries
    }

    var recentProviderIngestEventSummaries: [ProviderIngestEventSummary] {
        diagnosticsSnapshot.recentProviderIngestEventSummaries
    }

    var recentBackfillRunSummaries: [BackfillRunSummary] {
        diagnosticsSnapshot.recentBackfillRunSummaries
    }

    var recentAppLogEntries: [TokenmonAppLogEntry] {
        diagnosticsSnapshot.recentAppLogEntries
    }

    var onboardingStatuses: [TokenmonProviderOnboardingStatus] { diagnosticsSnapshot.onboardingStatuses }

    var providerInstallationPreferences: ProviderInstallationPreferences {
        diagnosticsSnapshot.providerInstallationPreferences
    }

    var appSettings: AppSettings { diagnosticsSnapshot.appSettings }

    var shouldShowUsageAnalyticsPrompt: Bool {
        !appSettings.usageAnalyticsEnabled && !appSettings.usageAnalyticsPromptDismissed
    }

    var shouldShowSetupRecommendations: Bool {
        setupRecommendations.isEmpty == false
    }

    var shouldAutoPresentOnboarding: Bool {
        !appSettings.firstRunSetupPromptShown
            && isLikelyFreshInstallForSetupPrompt
    }

    var launchAtLoginState: TokenmonLaunchAtLoginState { diagnosticsSnapshot.launchAtLoginState }

    var gameplayStartedAt: String? { diagnosticsSnapshot.databaseSummary?.gameplayStartedAt }

    var supportDirectoryPath: String {
        TokenmonDatabaseManager.supportDirectory(forDatabasePath: databasePath)
    }

    var cursorSyncArtifactsPath: String {
        URL(fileURLWithPath: supportDirectoryPath, isDirectory: true)
            .appendingPathComponent("Developer/CursorSync", isDirectory: true)
            .path
    }

    var cursorSyncAvailable: Bool {
        Self.resolveCursorSyncScriptURL(executablePath: executablePath) != nil
    }

    var logsDirectoryPath: String {
        TokenmonAppBehaviorLogger.logsDirectoryPath(supportDirectoryPath: supportDirectoryPath)
    }

    var appLogFilePath: String {
        TokenmonAppBehaviorLogger.logFilePath(supportDirectoryPath: supportDirectoryPath)
    }

    var inboxDirectoryPath: String {
        TokenmonDatabaseManager.inboxDirectory(forDatabasePath: databasePath)
    }

    var menuPresentation: TokenmonMenuPresentation {
        TokenmonMenuPresentationBuilder.build(
            snapshot: TokenmonMenuSnapshot(
                summary: summary,
                latestEncounter: latestEncounter,
                providerHealthSummaries: providerHealthSummaries,
                onboardingStatuses: onboardingStatuses,
                loadError: loadError
            ),
            providerStatusVisible: appSettings.providerStatusVisibility
        )
    }

    var liveSceneContext: TokenmonSceneContext {
        sceneContextWithSettings(
            TokenmonSceneContextBuilder.context(
                summary: summary,
                latestEncounter: latestEncounter,
                loadError: loadError,
                liveActivityUntil: liveActivityUntil
            )
        )
    }

    var popoverSceneContext: TokenmonSceneContext {
        TokenmonSceneContextResolver.popoverContext(
            displayedSceneContext: displayedSceneContext,
            liveSceneContext: liveSceneContext
        )
    }

    var restingSceneContext: TokenmonSceneContext {
        sceneContextWithSettings(
            TokenmonSceneContextBuilder.restingContext(
                summary: summary,
                latestEncounterField: latestEncounter?.field,
                loadError: loadError,
                liveActivityUntil: liveActivityUntil
            )
        )
    }

    func updateDisplayedSceneContext(_ context: TokenmonSceneContext) {
        guard displayedSceneContext != context else {
            return
        }
        displayedSceneContext = context
    }

    func consumePendingMenuBarEncounterAnimations() -> [RecentEncounterSummary] {
        let pending = pendingMenuBarEncounterAnimations
        pendingMenuBarEncounterAnimations = []
        return pending
    }

    private func sceneContextWithSettings(_ context: TokenmonSceneContext) -> TokenmonSceneContext {
        TokenmonSceneContext(
            sceneState: context.sceneState,
            fieldKind: context.fieldKind,
            fieldState: context.fieldState,
            effectState: context.effectState,
            wildState: context.wildState,
            wildAssetKey: context.wildAssetKey,
            showsFieldBackplate: appSettings.fieldBackplateEnabled
        )
    }

    private func enqueueMenuBarEncounterAnimations(_ encounters: [RecentEncounterSummary]) {
        guard encounters.isEmpty == false else {
            return
        }

        pendingMenuBarEncounterAnimations.append(contentsOf: encounters)
    }

    @discardableResult
    private func persist(settings: AppSettings) -> Bool {
        do {
            try databaseManager.saveAppSettings(settings)
            TokenmonL10n.setLocaleOverride(settings.languagePreference.localeIdentifier)
            TokenmonAppAppearanceController.apply(settings.appearancePreference)
            analyticsTracker.syncConsent(
                appSettings: settings,
                localeIdentifier: TokenmonL10n.activeLocale.identifier
            )
            updateDiagnosticsSnapshot { snapshot in
                snapshot.appSettings = settings
            }
            settingsMessage = nil
            settingsError = nil
            return true
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
            return false
        }
    }

    private func persist(providerInstallationPreferences: ProviderInstallationPreferences) {
        do {
            try databaseManager.saveProviderInstallationPreferences(providerInstallationPreferences)
            updateDiagnosticsSnapshot { snapshot in
                snapshot.providerInstallationPreferences = providerInstallationPreferences
            }
            refresh(reason: .surfaceOpened(.settings))
            settingsMessage = TokenmonL10n.string("settings.feedback.provider_paths_updated")
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
            settingsMessage = nil
        }
    }

    private func updateDiagnosticsSnapshot(_ update: (inout TokenmonDiagnosticsSnapshot) -> Void) {
        var snapshot = diagnosticsSnapshot
        update(&snapshot)
        diagnosticsSnapshot = snapshot
    }

    func overrideLaunchAtLoginStateForCapture(_ state: TokenmonLaunchAtLoginState) {
        updateDiagnosticsSnapshot { snapshot in
            snapshot.launchAtLoginState = state
        }
    }

    func hydrateSnapshotsForCapture(scopes: TokenmonRefreshScopes = .all) {
        var refreshed: TokenmonMenuRefreshResult?
        var isComplete = false

        Task {
            let launchAtLoginState = scopes.contains(.diagnostics) ? launchAtLoginStateProvider() : nil
            refreshed = try? await TokenmonMenuSnapshotLoader.load(
                databasePath: databasePath,
                executablePath: executablePath,
                scopes: scopes,
                providerInspector: providerInspector,
                launchAtLoginState: launchAtLoginState
            )
            isComplete = true
        }

        let deadline = Date().addingTimeInterval(3)
        while isComplete == false && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        if let refreshed {
            applyRefreshResult(refreshed)
        }
    }

    func hydrateRuntimeSnapshotForCapture() {
        do {
            let recentEncounterFeed = try databaseManager.recentEncounterSummaries(limit: 5)
            runtimeSnapshot = TokenmonRuntimeSnapshot(
                isLoaded: true,
                summary: try databaseManager.currentRunSummary(),
                latestEncounter: recentEncounterFeed.first,
                recentEncounterFeed: recentEncounterFeed,
                todayActivity: try databaseManager.todayActivitySummary(),
                providerHealthSummaries: [],
                ambientCompanionRoster: try databaseManager.ambientCompanionRoster(),
                raidDashboard: try databaseManager.raidDashboardSummary(),
                achievementBadges: try databaseManager.achievementBadgeSummaries(),
                nowCampSummary: try databaseManager.nowCampSummary()
            )
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func hydrateInsightsSnapshotForCapture() {
        do {
            let dexEntries = try databaseManager.dexEntrySummaries()
            let recentDomainEvents = try databaseManager.recentDomainEvents(limit: 24)
            let partyMembers = try databaseManager.partyMemberSummaries()
            insightsSnapshot = TokenmonInsightsSnapshot(
                isLoaded: true,
                dexEntries: dexEntries,
                recentCaptures: Array(
                    dexEntries
                        .filter { $0.status == .captured }
                        .sorted { ($0.lastCapturedAt ?? "") > ($1.lastCapturedAt ?? "") }
                        .prefix(16)
                ),
                fieldDistribution: try databaseManager.encounterFieldDistribution(),
                dailyTrend: try databaseManager.encounterDailyTrend(days: 7),
                tokenTotals: try databaseManager.tokenUsageTotals(),
                tokenUsageSourceSummary: try databaseManager.tokenUsageSourceSummary(),
                tokenByProviderToday: try databaseManager.tokenByProviderToday(),
                tokenHourlyRolling: try databaseManager.tokenHourlyRolling24(),
                recentSessions: try databaseManager.recentProviderSessions(limit: 30),
                recentDomainEventRecords: recentDomainEvents,
                partyMembers: partyMembers,
                partySpeciesIDs: Set(partyMembers.map(\.speciesID))
            )
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshNotificationAuthorizationState() {
        notificationCoordinator.fetchAuthorizationState { [weak self] state in
            guard let self else {
                return
            }
            self.notificationAuthorizationState = state
            self.logDebug(
                category: "notifications",
                event: "notification_authorization_state_refreshed",
                metadata: ["state": String(describing: state)]
            )
        }
    }

    private var setupRecommendations: [TokenmonSetupRecommendationItem] {
        TokenmonSetupRecommendationsBuilder.items(
            appSettings: appSettings,
            launchAtLoginState: launchAtLoginState,
            notificationAuthorizationState: notificationAuthorizationState
        )
    }

    private var isLikelyFreshInstallForSetupPrompt: Bool {
        guard let summary else {
            return false
        }

        return summary.providerSessions == 0
            && summary.usageSamples == 0
            && summary.totalEncounters == 0
    }

    private func runNotificationPreferenceFlow(isEnabled: Bool) {
        notificationCoordinator.notificationsPreferenceDidChange(isEnabled: isEnabled) { [weak self] message, error in
            guard let self else {
                return
            }
            self.settingsMessage = message
            self.settingsError = error
            self.refreshNotificationAuthorizationState()
        }
    }

    private func runUpdateNotificationPreferenceFlow(isEnabled: Bool) {
        notificationCoordinator.updateNotificationsPreferenceDidChange(isEnabled: isEnabled) { [weak self] message, error in
            guard let self else {
                return
            }
            self.settingsMessage = message
            self.settingsError = error
            self.refreshNotificationAuthorizationState()
        }
    }

    private func logDebug(category: String, event: String, metadata: [String: String] = [:]) {
        TokenmonAppBehaviorLogger.debug(
            category: category,
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    private func logInfo(category: String, event: String, metadata: [String: String] = [:]) {
        TokenmonAppBehaviorLogger.info(
            category: category,
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    private func logNotice(category: String, event: String, metadata: [String: String] = [:]) {
        TokenmonAppBehaviorLogger.notice(
            category: category,
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    private func logError(category: String, event: String, metadata: [String: String] = [:]) {
        TokenmonAppBehaviorLogger.error(
            category: category,
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    func emitAppOpenedAnalyticsIfNeeded() {
        guard !appOpenedAnalyticsEmitted, appSettings.usageAnalyticsEnabled else {
            return
        }

        analyticsTracker.captureAppOpened(
            summary: summary,
            latestEncounter: latestEncounter,
            providerHealthSummaries: providerHealthSummaries
        )
        appOpenedAnalyticsEmitted = true
    }

    private var providerHealthByProvider: [ProviderCode: ProviderHealthSummary] {
        Dictionary(uniqueKeysWithValues: providerHealthSummaries.map { ($0.provider, $0) })
    }

    private func providerHealthChanged(
        previous: ProviderHealthSummary?,
        current: ProviderHealthSummary
    ) -> Bool {
        guard let previous else {
            return false
        }

        return previous.sourceMode != current.sourceMode
            || previous.healthState != current.healthState
            || previous.liveGameplayArmed != current.liveGameplayArmed
    }

    private func forgePresetEncounter(
        provider: ProviderCode,
        field: FieldType? = nil,
        rarity: RarityTier,
        outcome: EncounterOutcome
    ) throws {
        let species = try presetSpecies(field: field, rarity: rarity)
        _ = try databaseManager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: provider,
                field: species.field,
                rarity: species.rarity,
                speciesID: species.id,
                outcome: outcome
            )
        )
    }

    private func presetSpecies(
        field: FieldType?,
        rarity: RarityTier
    ) throws -> SpeciesDefinition {
        if let field,
           let species = SpeciesCatalog.all.first(where: {
               $0.isActive && $0.field == field && $0.rarity == rarity
           }) {
            return species
        }

        if let species = SpeciesCatalog.all.first(where: {
            $0.isActive && $0.rarity == rarity
        }) {
            return species
        }

        throw TokenmonDeveloperToolsMutationError.missingForgeSpecies(
            field: field ?? .grassland,
            rarity: rarity
        )
    }
}

enum TokenmonDeveloperScenarioPreset: String, CaseIterable, Hashable {
    case encounterReady
    case starterShowcase
    case rarityShowcase
    case denseDexProgress
    case mixedOutcomes

    var title: String {
        switch self {
        case .encounterReady:
            return TokenmonL10n.string("developer.scenario.encounter_ready.title")
        case .starterShowcase:
            return TokenmonL10n.string("developer.scenario.starter_showcase.title")
        case .rarityShowcase:
            return TokenmonL10n.string("developer.scenario.rarity_showcase.title")
        case .denseDexProgress:
            return TokenmonL10n.string("developer.scenario.dense_dex_progress.title")
        case .mixedOutcomes:
            return TokenmonL10n.string("developer.scenario.mixed_outcomes.title")
        }
    }

    var subtitle: String {
        switch self {
        case .encounterReady:
            return TokenmonL10n.string("developer.scenario.encounter_ready.subtitle")
        case .starterShowcase:
            return TokenmonL10n.string("developer.scenario.starter_showcase.subtitle")
        case .rarityShowcase:
            return TokenmonL10n.string("developer.scenario.rarity_showcase.subtitle")
        case .denseDexProgress:
            return TokenmonL10n.string("developer.scenario.dense_dex_progress.subtitle")
        case .mixedOutcomes:
            return TokenmonL10n.string("developer.scenario.mixed_outcomes.subtitle")
        }
    }

    var successMessage: String {
        switch self {
        case .encounterReady:
            return TokenmonL10n.string("developer.scenario.encounter_ready.success")
        case .starterShowcase:
            return TokenmonL10n.string("developer.scenario.starter_showcase.success")
        case .rarityShowcase:
            return TokenmonL10n.string("developer.scenario.rarity_showcase.success")
        case .denseDexProgress:
            return TokenmonL10n.string("developer.scenario.dense_dex_progress.success")
        case .mixedOutcomes:
            return TokenmonL10n.string("developer.scenario.mixed_outcomes.success")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum TokenmonCursorSyncError: Error, LocalizedError {
    case scriptUnavailable
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "Cursor sync script is unavailable in the current repository context"
        case .executionFailed(let message):
            return message
        }
    }
}

private enum TokenmonCursorSyncPresentation {
    case manual
    case background
}

private extension TokenmonMenuModel {
    @MainActor
    func performCursorUsageSync(_ presentation: TokenmonCursorSyncPresentation) async {
        guard cursorSyncAvailable else {
            if presentation == .manual {
                settingsError = "Cursor sync script is not available from this Tokenmon build"
                settingsMessage = nil
                refresh(reason: .manual)
            }
            return
        }

        if presentation == .manual {
            settingsMessage = TokenmonL10n.string("settings.feedback.cursor_sync_started")
            settingsError = nil
        }

        let databasePath = self.databasePath
        let artifactsPath = self.cursorSyncArtifactsPath
        let executablePath = self.executablePath

        do {
            let output = try await Self.runCursorSyncProcess(
                databasePath: databasePath,
                artifactsPath: artifactsPath,
                executablePath: executablePath
            )

            let acceptedCount = Int(Self.syncOutputValue(for: "accepted", in: output) ?? "0") ?? 0

            if acceptedCount > 0 {
                recordLiveActivityPulse()
            }

            switch presentation {
            case .manual:
                settingsMessage = Self.cursorSyncMessage(from: output)
                settingsError = nil
                refresh(reason: .manual)
            case .background:
                if acceptedCount > 0 {
                    refresh(reason: .manual)
                }
            }
        } catch {
            switch presentation {
            case .manual:
                settingsError = error.localizedDescription
                settingsMessage = nil
                refresh(reason: .manual)
            case .background:
                TokenmonAppBehaviorLogger.debug(
                    category: "providers",
                    event: "cursor_background_sync_failed",
                    metadata: ["error": error.localizedDescription],
                    supportDirectoryPath: supportDirectoryPath
                )
            }
        }
    }

    nonisolated static func runCursorSyncProcess(
        databasePath: String,
        artifactsPath: String,
        executablePath: String
    ) async throws -> String {
        guard let scriptURL = resolveCursorSyncScriptURL(executablePath: executablePath) else {
            throw TokenmonCursorSyncError.scriptUnavailable
        }

        let result = try await TokenmonAsyncProcessRunner.run(
            TokenmonAsyncProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "python3",
                    scriptURL.path,
                    "--artifact-dir", artifactsPath,
                    "--db", databasePath,
                    "--tokenmon-app-bin", executablePath,
                ],
                currentDirectoryURL: scriptURL.deletingLastPathComponent().deletingLastPathComponent()
            )
        )

        let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.terminationStatus == 0 else {
            let detail = stderr.isEmpty ? stdout : stderr
            throw TokenmonCursorSyncError.executionFailed(
                detail.isEmpty ? "Cursor sync failed with status \(result.terminationStatus)" : detail
            )
        }

        return stdout
    }

    nonisolated static func cursorSyncMessage(from output: String) -> String {
        let accepted = syncOutputValue(for: "accepted", in: output) ?? "0"
        let usageSamples = syncOutputValue(for: "account_usage_samples", in: output)
            ?? syncOutputValue(for: "usage_samples", in: output)
            ?? "0"
        if let gameplayNote = syncOutputValue(for: "gameplay_note", in: output) {
            return "Cursor sync complete: \(accepted) accepted, \(usageSamples) account samples. \(gameplayNote)"
        }
        return "Cursor sync complete: \(accepted) accepted, \(usageSamples) account samples."
    }

    nonisolated static func syncOutputValue(for key: String, in output: String) -> String? {
        let prefix = "\(key): "
        for line in output.split(separator: "\n") {
            guard line.hasPrefix(prefix) else {
                continue
            }
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    nonisolated static func resolveCursorSyncScriptURL(executablePath: String) -> URL? {
        let fm = FileManager.default
        if let bundled = TokenmonAppResourceLocator.resourceURL(relativePath: "cursor-usage-prototype") {
            return bundled
        }
        var candidates: [URL] = [URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)]
        var cursor = URL(fileURLWithPath: executablePath, isDirectory: false).deletingLastPathComponent()
        for _ in 0..<8 {
            candidates.append(cursor)
            cursor.deleteLastPathComponent()
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            var current = candidate
            for _ in 0..<10 {
                let gitPath = current.appendingPathComponent(".git").path
                if fm.fileExists(atPath: gitPath) {
                    let scriptURL = current
                        .appendingPathComponent("scripts", isDirectory: true)
                        .appendingPathComponent("cursor-usage-prototype", isDirectory: false)
                    if fm.isExecutableFile(atPath: scriptURL.path) {
                        return scriptURL
                    }
                    break
                }
                current.deleteLastPathComponent()
            }
        }

        return nil
    }
}

enum TokenmonSceneContextResolver {
    static func popoverContext(
        displayedSceneContext: TokenmonSceneContext?,
        liveSceneContext: TokenmonSceneContext
    ) -> TokenmonSceneContext {
        displayedSceneContext ?? liveSceneContext
    }
}

struct TokenmonLaunchAtLoginState: Equatable, Sendable {
    let isSupported: Bool
    let isEnabled: Bool
    let reason: String
    let showsOpenSystemSettingsAction: Bool

    static func unsupported(reason: String) -> TokenmonLaunchAtLoginState {
        TokenmonLaunchAtLoginState(
            isSupported: false,
            isEnabled: false,
            reason: reason,
            showsOpenSystemSettingsAction: false
        )
    }

    init(
        isSupported: Bool,
        isEnabled: Bool,
        reason: String,
        showsOpenSystemSettingsAction: Bool = false
    ) {
        self.isSupported = isSupported
        self.isEnabled = isEnabled
        self.reason = reason
        self.showsOpenSystemSettingsAction = showsOpenSystemSettingsAction
    }
}

enum TokenmonLaunchAtLoginFallbackPolicy: Equatable, Sendable {
    case nativeOnly
    case developmentFallbackAllowed

    var allowsLegacyFallback: Bool {
        self == .developmentFallbackAllowed
    }
}

enum TokenmonLaunchAtLoginNativeStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case statusUnavailable

    init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notRegistered:
            self = .notRegistered
        case .notFound:
            self = .notFound
        @unknown default:
            self = .statusUnavailable
        }
    }
}

struct TokenmonLaunchAtLoginDependencies {
    let bundle: Bundle
    let fileManager: FileManager
    let homeDirectory: URL
    let nativeStatusProvider: () -> TokenmonLaunchAtLoginNativeStatus
    let nativeSetter: (Bool) throws -> Void
    let fallbackPolicy: TokenmonLaunchAtLoginFallbackPolicy
    let supportDirectoryPath: String

    init(
        bundle: Bundle,
        fileManager: FileManager,
        homeDirectory: URL,
        nativeStatusProvider: @escaping () -> TokenmonLaunchAtLoginNativeStatus,
        nativeSetter: @escaping (Bool) throws -> Void,
        fallbackPolicy: TokenmonLaunchAtLoginFallbackPolicy = .developmentFallbackAllowed,
        supportDirectoryPath: String = TokenmonDatabaseManager.supportDirectory()
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.nativeStatusProvider = nativeStatusProvider
        self.nativeSetter = nativeSetter
        self.fallbackPolicy = fallbackPolicy
        self.supportDirectoryPath = supportDirectoryPath
    }

    static func live() -> TokenmonLaunchAtLoginDependencies {
        TokenmonLaunchAtLoginDependencies(
            bundle: .main,
            fileManager: .default,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            nativeStatusProvider: {
                TokenmonLaunchAtLoginNativeStatus(serviceStatus: SMAppService.mainApp.status)
            },
            nativeSetter: { enabled in
                let service = SMAppService.mainApp
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            },
            fallbackPolicy: TokenmonBuildInfo.current.buildConfiguration == .debug
                ? .developmentFallbackAllowed
                : .nativeOnly
        )
    }
}

enum TokenmonLaunchAtLoginController {
    static func snapshot() -> TokenmonLaunchAtLoginState {
        snapshot(using: .live())
    }

    static func snapshot(
        using dependencies: TokenmonLaunchAtLoginDependencies
    ) -> TokenmonLaunchAtLoginState {
        guard isSupportedEnvironment(bundle: dependencies.bundle) else {
            return .unsupported(reason: TokenmonL10n.string("settings.launch_at_login.reason.installed_only"))
        }

        let fallbackAgent = TokenmonLaunchAtLoginFallbackAgent(dependencies: dependencies)
        if dependencies.fallbackPolicy.allowsLegacyFallback == false {
            cleanupLegacyFallbackIfNeeded(using: dependencies)
        }
        let nativeStatus = dependencies.nativeStatusProvider()
        logDebug(
            dependencies: dependencies,
            event: "launch_at_login_native_status_snapshot",
            metadata: [
                "status": nativeStatus.logLabel,
                "fallback_policy": dependencies.fallbackPolicy.logLabel,
            ]
        )
        switch nativeStatus {
        case .enabled:
            return TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: true,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.enabled")
            )
        case .requiresApproval:
            return TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.requires_approval"),
                showsOpenSystemSettingsAction: true
            )
        case .notRegistered:
            return TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
            )
        case .notFound:
            if dependencies.fallbackPolicy.allowsLegacyFallback {
                if fallbackAgent.isSupported {
                    try? fallbackAgent.migrateIfNeeded()
                    let isEnabled = fallbackAgent.isEnabled
                    return TokenmonLaunchAtLoginState(
                        isSupported: true,
                        isEnabled: isEnabled,
                        reason: TokenmonL10n.string(
                            isEnabled
                                ? "settings.launch_at_login.reason.enabled"
                                : "settings.launch_at_login.reason.disabled"
                        )
                    )
                }

                return .unsupported(reason: TokenmonL10n.string("settings.launch_at_login.reason.installed_only"))
            }

            logInfo(
                dependencies: dependencies,
                event: "launch_at_login_native_status_treated_as_unregistered"
            )
            return TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
            )
        case .statusUnavailable:
            if dependencies.fallbackPolicy.allowsLegacyFallback {
                if fallbackAgent.isSupported {
                    try? fallbackAgent.migrateIfNeeded()
                    let isEnabled = fallbackAgent.isEnabled
                    return TokenmonLaunchAtLoginState(
                        isSupported: true,
                        isEnabled: isEnabled,
                        reason: TokenmonL10n.string(
                            isEnabled
                                ? "settings.launch_at_login.reason.enabled"
                                : "settings.launch_at_login.reason.disabled"
                        )
                    )
                }

                return .unsupported(reason: TokenmonL10n.string("settings.launch_at_login.reason.installed_only"))
            }

            logInfo(
                dependencies: dependencies,
                event: "launch_at_login_native_path_unsupported",
                metadata: ["status": nativeStatus.logLabel]
            )
            return TokenmonLaunchAtLoginState(
                isSupported: false,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.status_unavailable"),
                showsOpenSystemSettingsAction: true
            )
        }
    }

    static func setEnabled(_ enabled: Bool) throws -> TokenmonLaunchAtLoginState {
        try setEnabled(enabled, using: .live())
    }

    static func setEnabled(
        _ enabled: Bool,
        using dependencies: TokenmonLaunchAtLoginDependencies
    ) throws -> TokenmonLaunchAtLoginState {
        guard isSupportedEnvironment(bundle: dependencies.bundle) else {
            return snapshot(using: dependencies)
        }

        let fallbackAgent = TokenmonLaunchAtLoginFallbackAgent(dependencies: dependencies)
        if dependencies.fallbackPolicy.allowsLegacyFallback == false {
            cleanupLegacyFallbackIfNeeded(using: dependencies)
        }
        switch dependencies.nativeStatusProvider() {
        case .enabled, .requiresApproval, .notRegistered:
            try fallbackAgent.disableIfPresent()
            logInfo(
                dependencies: dependencies,
                event: "launch_at_login_native_registration_attempted",
                metadata: ["enabled": String(enabled)]
            )
            try dependencies.nativeSetter(enabled)
        case .notFound:
            if dependencies.fallbackPolicy.allowsLegacyFallback {
                guard fallbackAgent.isSupported else {
                    return snapshot(using: dependencies)
                }
                try fallbackAgent.setEnabled(enabled)
                return snapshot(using: dependencies)
            }

            if enabled {
                logInfo(
                    dependencies: dependencies,
                    event: "launch_at_login_native_registration_attempted",
                    metadata: ["enabled": String(enabled)]
                )
                try dependencies.nativeSetter(true)
            }
        case .statusUnavailable:
            guard dependencies.fallbackPolicy.allowsLegacyFallback, fallbackAgent.isSupported else {
                logInfo(
                    dependencies: dependencies,
                    event: "launch_at_login_native_path_unsupported",
                    metadata: [
                        "status": dependencies.nativeStatusProvider().logLabel,
                        "enabled": String(enabled),
                    ]
                )
                return snapshot(using: dependencies)
            }
            try fallbackAgent.setEnabled(enabled)
        }

        return snapshot(using: dependencies)
    }

    @discardableResult
    static func cleanupLegacyFallbackIfNeeded(using dependencies: TokenmonLaunchAtLoginDependencies = .live()) -> Bool {
        guard dependencies.fallbackPolicy.allowsLegacyFallback == false else {
            return false
        }

        let fallbackAgent = TokenmonLaunchAtLoginFallbackAgent(dependencies: dependencies)
        guard fallbackAgent.isPresent else {
            return false
        }

        do {
            try fallbackAgent.disableIfPresent()
            logInfo(
                dependencies: dependencies,
                event: "launch_at_login_legacy_launch_agent_removed"
            )
            return true
        } catch {
            logError(
                dependencies: dependencies,
                event: "launch_at_login_legacy_launch_agent_removal_failed",
                metadata: ["error": error.localizedDescription]
            )
            return false
        }
    }

    private static func isSupportedEnvironment(bundle: Bundle) -> Bool {
        let bundleURL = bundle.bundleURL
        return bundleURL.pathExtension.lowercased() == "app" && bundle.bundleIdentifier != nil
    }

    private static func logDebug(
        dependencies: TokenmonLaunchAtLoginDependencies,
        event: String,
        metadata: [String: String] = [:]
    ) {
        TokenmonAppBehaviorLogger.debug(
            category: "launch_at_login",
            event: event,
            metadata: metadata,
            supportDirectoryPath: dependencies.supportDirectoryPath
        )
    }

    private static func logInfo(
        dependencies: TokenmonLaunchAtLoginDependencies,
        event: String,
        metadata: [String: String] = [:]
    ) {
        TokenmonAppBehaviorLogger.info(
            category: "launch_at_login",
            event: event,
            metadata: metadata,
            supportDirectoryPath: dependencies.supportDirectoryPath
        )
    }

    private static func logError(
        dependencies: TokenmonLaunchAtLoginDependencies,
        event: String,
        metadata: [String: String] = [:]
    ) {
        TokenmonAppBehaviorLogger.error(
            category: "launch_at_login",
            event: event,
            metadata: metadata,
            supportDirectoryPath: dependencies.supportDirectoryPath
        )
    }
}

private struct TokenmonLaunchAtLoginFallbackAgent {
    private let bundleURL: URL
    private let bundleIdentifier: String
    private let executableURL: URL
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(dependencies: TokenmonLaunchAtLoginDependencies) {
        bundleURL = dependencies.bundle.bundleURL.standardizedFileURL
        bundleIdentifier = dependencies.bundle.bundleIdentifier ?? "com.aroido.tokenmon"
        executableURL = Self.resolveExecutableURL(for: dependencies.bundle)
        fileManager = dependencies.fileManager
        homeDirectory = dependencies.homeDirectory.standardizedFileURL
    }

    var isSupported: Bool {
        let globalApplications = URL(fileURLWithPath: "/Applications", isDirectory: true).path + "/"
        let userApplications = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path + "/"
        let bundlePath = bundleURL.path

        return bundlePath.hasPrefix(globalApplications) || bundlePath.hasPrefix(userApplications)
    }

    var isEnabled: Bool {
        guard isSupported else {
            return false
        }

        return configuredBundlePath == bundleURL.path
    }

    var isPresent: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writePlist()
        } else {
            try disableIfPresent()
        }
    }

    func disableIfPresent() throws {
        guard fileManager.fileExists(atPath: plistURL.path) else {
            return
        }

        try fileManager.removeItem(at: plistURL)
    }

    func migrateIfNeeded() throws {
        guard needsMigration else {
            return
        }

        try writePlist()
    }

    private var configuredBundlePath: String? {
        guard
            let arguments = configuredProgramArguments,
            let configuredPath = Self.bundlePath(fromProgramArguments: arguments)
        else {
            return nil
        }

        return configuredPath
    }

    private var configuredProgramArguments: [String]? {
        configuredPayload?["ProgramArguments"] as? [String]
    }

    private var configuredAssociatedBundleIdentifiers: [String]? {
        configuredPayload?["AssociatedBundleIdentifiers"] as? [String]
    }

    private var configuredPayload: [String: Any]? {
        guard
            let data = try? Data(contentsOf: plistURL),
            let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }

        return payload
    }

    private var desiredProgramArguments: [String] {
        [executableURL.path]
    }

    private var desiredAssociatedBundleIdentifiers: [String] {
        [bundleIdentifier]
    }

    private var needsMigration: Bool {
        configuredBundlePath == bundleURL.path && (
            configuredProgramArguments != desiredProgramArguments ||
                configuredAssociatedBundleIdentifiers != desiredAssociatedBundleIdentifiers
        )
    }

    private func writePlist() throws {
        let launchAgentsDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let payload: [String: Any] = [
            "AssociatedBundleIdentifiers": desiredAssociatedBundleIdentifiers,
            "Label": label,
            "LimitLoadToSessionType": ["Aqua"],
            "ProcessType": "Interactive",
            "ProgramArguments": desiredProgramArguments,
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    private var label: String {
        "\(bundleIdentifier).launch-at-login"
    }

    private var plistURL: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    private static func resolveExecutableURL(for bundle: Bundle) -> URL {
        if let executableURL = bundle.executableURL {
            return executableURL.standardizedFileURL
        }

        let executableName = (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
            ?? bundle.bundleURL.deletingPathExtension().lastPathComponent
        return bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)
            .standardizedFileURL
    }

    private static func bundlePath(fromProgramArguments arguments: [String]) -> String? {
        guard let firstArgument = arguments.first else {
            return nil
        }

        let firstURL = URL(fileURLWithPath: firstArgument).standardizedFileURL
        if firstURL.path == "/usr/bin/open" {
            guard let configuredPath = arguments.last else {
                return nil
            }

            return URL(fileURLWithPath: configuredPath).standardizedFileURL.path
        }

        let macOSDirectoryURL = firstURL.deletingLastPathComponent()
        let contentsDirectoryURL = macOSDirectoryURL.deletingLastPathComponent()
        guard
            macOSDirectoryURL.lastPathComponent == "MacOS",
            contentsDirectoryURL.lastPathComponent == "Contents"
        else {
            return nil
        }

        return contentsDirectoryURL.deletingLastPathComponent().standardizedFileURL.path
    }
}

private extension TokenmonLaunchAtLoginNativeStatus {
    var logLabel: String {
        switch self {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requires_approval"
        case .notRegistered:
            return "not_registered"
        case .notFound:
            return "not_found"
        case .statusUnavailable:
            return "status_unavailable"
        }
    }
}

private extension TokenmonLaunchAtLoginFallbackPolicy {
    var logLabel: String {
        switch self {
        case .nativeOnly:
            return "native_only"
        case .developmentFallbackAllowed:
            return "development_fallback_allowed"
        }
    }
}
