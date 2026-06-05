import AppKit
import Foundation
import ScreenCaptureKit
import SwiftUI
import TokenmonDomain
import TokenmonOtelProviders
import TokenmonPersistence
import TokenmonProviders

@MainActor
enum TokenmonAppStartupServices {
    static func startNotificationAwareUpdateServices(
        notificationCoordinator: TokenmonCaptureNotificationCoordinating,
        appUpdater: TokenmonAppUpdaterStarting
    ) {
        notificationCoordinator.start()
        appUpdater.start()
    }
}

@MainActor
final class TokenmonSceneDebugController: ObservableObject {
    struct StatusOffsetTuning: Equatable, Sendable {
        var x: Double = 0
        var y: Double = 0
    }

    static let shared = TokenmonSceneDebugController()

    @Published var applyToMenuBar = false
    @Published var previewFieldKind: TokenmonSceneFieldKind = .grassland
    @Published var previewSceneState: TokenmonSceneState = .exploring
    @Published var previewFieldState: TokenmonFieldState = .exploring
    @Published var previewEffectState: TokenmonEffectState = .none
    @Published var previewWildState: TokenmonWildState = .hidden
    @Published var previewWildAssetKey: String?
    @Published private var statusOffsetTunings: [TokenmonSceneFieldKind: StatusOffsetTuning] = [
        .grassland: StatusOffsetTuning(),
        .sky: StatusOffsetTuning(),
        .coast: StatusOffsetTuning(),
        .ice: StatusOffsetTuning(),
        .unavailable: StatusOffsetTuning(),
    ]

    private init() {}

    func menuBarContext(default defaultContext: TokenmonSceneContext) -> TokenmonSceneContext {
        guard applyToMenuBar else {
            return defaultContext
        }

        return TokenmonSceneContext(
            sceneState: previewSceneState,
            fieldKind: previewFieldKind,
            fieldState: previewFieldState,
            effectState: previewEffectState,
            wildState: previewWildState,
            wildAssetKey: previewWildAssetKey ?? defaultContext.wildAssetKey,
            showsFieldBackplate: defaultContext.showsFieldBackplate
        )
    }

    func resetMenuBarPreview() {
        applyToMenuBar = false
        previewFieldKind = .grassland
        previewSceneState = .exploring
        previewFieldState = .exploring
        previewEffectState = .none
        previewWildState = .hidden
        previewWildAssetKey = nil
    }

    func selectField(_ field: TokenmonSceneFieldKind) {
        previewFieldKind = field
    }

    func resetStatusOffsets() {
        statusOffsetTunings[previewFieldKind] = StatusOffsetTuning()
    }

    func statusOffset(for field: TokenmonSceneFieldKind) -> CGSize {
        let tuning = statusOffsetTunings[field] ?? StatusOffsetTuning()
        return CGSize(width: tuning.x, height: tuning.y)
    }

    func setStatusOffsetX(_ value: Double, for field: TokenmonSceneFieldKind) {
        var tuning = statusOffsetTunings[field] ?? StatusOffsetTuning()
        tuning.x = value
        statusOffsetTunings[field] = tuning
    }

    func setStatusOffsetY(_ value: Double, for field: TokenmonSceneFieldKind) {
        var tuning = statusOffsetTunings[field] ?? StatusOffsetTuning()
        tuning.y = value
        statusOffsetTunings[field] = tuning
    }

    func statusOffsetX(for field: TokenmonSceneFieldKind) -> Double {
        statusOffsetTunings[field]?.x ?? 0
    }

    func statusOffsetY(for field: TokenmonSceneFieldKind) -> Double {
        statusOffsetTunings[field]?.y ?? 0
    }
}

@MainActor
final class TokenmonAppController {
    static let shared = TokenmonAppController()
    private static let cursorSyncIntervalNanoseconds: UInt64 = 20_000_000_000

    let sceneDebugController = TokenmonSceneDebugController.shared
    let menuModel: TokenmonMenuModel
    let appUpdater: TokenmonAppUpdater

    private let captureNotificationCoordinator: TokenmonCaptureNotificationCoordinator
    private let analyticsTracker: TokenmonAnalyticsTracking
    private var geminiSupervisor: GeminiOtelReceiverSupervisor?
    private var claudeTranscriptLiveObserver: ClaudeTranscriptLiveObserver?
    private var codexSessionStoreObserver: CodexSessionStoreObserver?
    private var antigravityLocalRPCObserver: AntigravityLocalRPCObserver?
    private var codexSessionsRootPath: String?
    private var startupTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var cursorSyncTask: Task<Void, Never>?

    private let collectionNavigationState = TokenmonCollectionNavigationState()
    private lazy var statusItemController: TokenmonStatusItemController = {
        let controller = TokenmonStatusItemController(
            model: menuModel,
            debugController: sceneDebugController
        )
        controller.setPopoverRootView(makePopoverRootView(controller: controller))
        return controller
    }()

    private var collectionWindowController: TokenmonHostingWindowController?
    private var settingsWindowController: TokenmonHostingWindowController?
    private var onboardingWindowController: TokenmonHostingWindowController?
    private var onboardingWindowCloseObserver: NSObjectProtocol?
    private var developerWindowController: TokenmonHostingWindowController?

    private init() {
        let databasePath = TokenmonDatabaseManager.defaultPath()
        let analyticsTracker = TokenmonPostHogAnalyticsTracker(databasePath: databasePath)
        let notificationCoordinator = TokenmonCaptureNotificationCoordinator()
        let menuModel = TokenmonMenuModel(
            databasePath: databasePath,
            notificationCoordinator: notificationCoordinator,
            analyticsTracker: analyticsTracker
        )
        let appUpdater = TokenmonAppUpdater(
            settingsProvider: { menuModel.appSettings },
            notificationCoordinator: notificationCoordinator,
            analyticsTracker: analyticsTracker,
            startImmediately: false
        )

        captureNotificationCoordinator = notificationCoordinator
        self.analyticsTracker = analyticsTracker
        self.appUpdater = appUpdater
        self.menuModel = menuModel
        notificationCoordinator.onOpenCapturedSpecies = { [weak self] speciesID in
            self?.showDexWindow(selecting: speciesID)
        }
        notificationCoordinator.onCaptureNotificationOpened = { [weak self] speciesID, encounterID in
            self?.captureNotificationOpened(speciesID: speciesID, encounterID: encounterID)
        }
        notificationCoordinator.onOpenAvailableUpdate = { [weak appUpdater] _ in
            NSApp.activate(ignoringOtherApps: true)
            appUpdater?.checkForUpdates()
        }
    }

    func start() {
        let startupStartedAt = Date()
        TokenmonAppBehaviorLogger.notice(
            category: "app",
            event: "app_controller_started",
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        TokenmonAppAppearanceController.apply(menuModel.appSettings.appearancePreference)
        statusItemController.start()
        TokenmonAppBehaviorLogger.debug(
            category: "startup",
            event: "startup_phase_completed",
            metadata: [
                "phase": "status_item_started",
                "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupStartedAt),
            ],
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        TokenmonAppStartupServices.startNotificationAwareUpdateServices(
            notificationCoordinator: captureNotificationCoordinator,
            appUpdater: appUpdater
        )
        TokenmonAppBehaviorLogger.debug(
            category: "startup",
            event: "startup_phase_completed",
            metadata: [
                "phase": "notification_coordinator_started",
                "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupStartedAt),
            ],
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        TokenmonAppBehaviorLogger.debug(
            category: "startup",
            event: "startup_phase_completed",
            metadata: [
                "phase": "app_updater_started",
                "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupStartedAt),
            ],
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        runStartupWindowAutomationIfRequested()

        let databasePath = menuModel.currentDatabasePath
        let supportDirectoryPath = menuModel.supportDirectoryPath
        let executablePath = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        startupTask?.cancel()
        recoveryTask?.cancel()
        cursorSyncTask?.cancel()
        cursorSyncTask = nil
        recoveryTask = nil
        startupTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            let startupTaskStartedAt = Date()

            func logStartupPhase(_ phase: String, startedAt: Date, metadata: [String: String] = [:]) {
                var combined = metadata
                combined["phase"] = phase
                combined["duration_ms"] = TokenmonAppBehaviorLogger.durationMillisecondsString(since: startedAt)
                combined["elapsed_ms"] = TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupTaskStartedAt)
                TokenmonAppBehaviorLogger.debug(
                    category: "startup",
                    event: "startup_phase_completed",
                    metadata: combined,
                    supportDirectoryPath: supportDirectoryPath
                )
            }

            await self.menuModel.waitForRefreshToFinish()
            logStartupPhase("initial_refresh_wait", startedAt: startupTaskStartedAt)

            var phaseStartedAt = Date()
            let databaseManager = TokenmonDatabaseManager(path: databasePath)
            let preferences = (try? databaseManager.providerInstallationPreferences()) ?? ProviderInstallationPreferences()
            logStartupPhase("load_preferences", startedAt: phaseStartedAt)

            phaseStartedAt = Date()
            let autoSetupResults = TokenmonProviderOnboarding.autoConfigureDetectedProviders(
                databasePath: databasePath,
                executablePath: executablePath,
                preferences: preferences
            )
            let onboardingStatuses = TokenmonProviderOnboarding.inspectAll(
                databasePath: databasePath,
                executablePath: executablePath,
                preferences: preferences
            )
            for result in autoSetupResults {
                if let error = result.error {
                    TokenmonAppBehaviorLogger.notice(
                        category: "providers",
                        event: "provider_auto_setup_failed",
                        metadata: [
                            "provider": result.provider.rawValue,
                            "message": result.message,
                            "error": error,
                        ],
                        supportDirectoryPath: supportDirectoryPath
                    )
                } else {
                    TokenmonAppBehaviorLogger.notice(
                        category: "providers",
                        event: "provider_auto_setup_completed",
                        metadata: [
                            "provider": result.provider.rawValue,
                            "configured": result.configured ? "yes" : "no",
                            "message": result.message,
                        ],
                        supportDirectoryPath: supportDirectoryPath
                    )
                }
            }
            await MainActor.run {
                for result in autoSetupResults {
                    let onboardingStatus = onboardingStatuses.first { $0.provider == result.provider }
                    self.analyticsTracker.captureProviderSetupResult(
                        provider: result.provider,
                        trigger: .auto,
                        result: result.configured ? .completed : .failed,
                        cliInstalled: onboardingStatus?.cliInstalled ?? false,
                        isPartial: onboardingStatus?.isPartial ?? false
                    )
                }
            }
            logStartupPhase("provider_auto_setup", startedAt: phaseStartedAt, metadata: ["result_count": "\(autoSetupResults.count)"])

            phaseStartedAt = Date()
            try? databaseManager.markLiveGameplayStarted()
            logStartupPhase("mark_live_gameplay_started", startedAt: phaseStartedAt)

            phaseStartedAt = Date()
            let claudeDiscovery = TokenmonProviderDiscovery.discover(provider: .claude, preferences: preferences)
            let codexDiscovery = TokenmonProviderDiscovery.discover(provider: .codex, preferences: preferences)
            let cursorDiscovery = TokenmonProviderDiscovery.discover(provider: .cursor, preferences: preferences)
            let claudeProjectsRootPath = URL(fileURLWithPath: claudeDiscovery.configurationPath, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
                .path
            let sessionsRootPath = CodexSessionStorageLocator.sessionStorageRootPath(
                config: CodexSessionStorageLocatorConfig(
                    configurationRootPath: codexDiscovery.configurationPath
                )
            )
            logStartupPhase(
                "resolve_provider_paths",
                startedAt: phaseStartedAt,
                metadata: ["cursor_detected": cursorDiscovery.executableExists ? "yes" : "no"]
            )

            phaseStartedAt = Date()
            let shouldStartClaudeTranscriptObserver = TokenmonProviderOnboarding
                .shouldStartClaudePassiveTranscriptObserver(preferences: preferences)
            let claudeObserver: ClaudeTranscriptLiveObserver?
            if shouldStartClaudeTranscriptObserver {
                let observer = ClaudeTranscriptLiveObserver(
                    config: ClaudeTranscriptLiveObserverConfig(
                        projectsRootPath: claudeProjectsRootPath,
                        outputPath: TokenmonDatabaseManager.inboxPath(provider: .claude, databasePath: databasePath),
                        onActivityPulse: { [weak self] in
                            Task { @MainActor [weak self] in
                                self?.menuModel.recordLiveActivityPulse()
                            }
                        }
                    )
                )
                observer.startAsync()
                claudeObserver = observer
            } else {
                claudeObserver = nil
            }
            logStartupPhase(
                "claude_transcript_observer_started",
                startedAt: phaseStartedAt,
                metadata: ["started": shouldStartClaudeTranscriptObserver ? "yes" : "no"]
            )

            phaseStartedAt = Date()
            let observer = CodexSessionStoreObserver(
                config: CodexSessionStoreObserverConfig(
                    sessionsRootPath: sessionsRootPath,
                    outputPath: TokenmonDatabaseManager.inboxPath(provider: .codex),
                    onActivityPulse: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.menuModel.recordLiveActivityPulse()
                        }
                    }
                )
            )
            observer.startAsync()
            logStartupPhase("codex_session_observer_started", startedAt: phaseStartedAt)

            phaseStartedAt = Date()
            let antigravityObserver = AntigravityLocalRPCObserver(
                config: AntigravityLocalRPCObserverConfig(
                    outputPath: TokenmonDatabaseManager.inboxPath(provider: .antigravity, databasePath: databasePath),
                    onHealthChange: { [weak self] health in
                        try? TokenmonDatabaseManager(path: databasePath).upsertProviderHealth(
                            provider: .antigravity,
                            sourceMode: health.sourceMode,
                            healthState: health.healthState,
                            message: health.message,
                            lastSuccessAt: health.lastSuccessAt,
                            lastErrorAt: health.lastErrorAt,
                            lastErrorCode: health.lastErrorCode,
                            lastErrorSummary: health.lastErrorSummary
                        )
                        Task { @MainActor [weak self] in
                            self?.menuModel.refresh(reason: .inboxEvent)
                        }
                    },
                    onActivityPulse: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.menuModel.recordLiveActivityPulse()
                        }
                    }
                )
            )
            antigravityObserver.startAsync()
            logStartupPhase("antigravity_rpc_observer_started", startedAt: phaseStartedAt)

            await MainActor.run {
                let mainActorPhaseStartedAt = Date()
                self.claudeTranscriptLiveObserver = claudeObserver
                self.codexSessionsRootPath = sessionsRootPath
                self.codexSessionStoreObserver = observer
                self.antigravityLocalRPCObserver = antigravityObserver

                let liveMonitoringStartedAt = Date()
                self.menuModel.activateLiveMonitoring()
                logStartupPhase(
                    "activate_live_monitoring",
                    startedAt: liveMonitoringStartedAt,
                    metadata: ["elapsed_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupTaskStartedAt)]
                )

                if cursorDiscovery.executableExists {
                    let cursorSyncStartedAt = Date()
                    self.cursorSyncTask = Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }

                        await self.menuModel.syncCursorUsageInBackground()

                        while Task.isCancelled == false {
                            do {
                                try await Task.sleep(nanoseconds: Self.cursorSyncIntervalNanoseconds)
                            } catch {
                                return
                            }

                            guard Task.isCancelled == false else {
                                return
                            }

                            await self.menuModel.syncCursorUsageInBackground()
                        }
                    }
                    logStartupPhase(
                        "cursor_background_sync_started",
                        startedAt: cursorSyncStartedAt,
                        metadata: ["interval_seconds": "20"]
                    )
                }

                let geminiSetupStartedAt = Date()
                let supervisor = GeminiOtelReceiverSupervisor(
                    dataSource: databaseManager,
                    inboxPath: TokenmonDatabaseManager.inboxPath(provider: .gemini, databasePath: databasePath),
                    claudeInboxPath: TokenmonDatabaseManager.inboxPath(provider: .claude, databasePath: databasePath)
                )
                self.geminiSupervisor = supervisor
                self.menuModel.observeGeminiReceiver(supervisor)
                logStartupPhase(
                    "prepare_gemini_supervisor",
                    startedAt: geminiSetupStartedAt,
                    metadata: ["elapsed_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupTaskStartedAt)]
                )

                Task { @MainActor in
                    await supervisor.start()
                }

                logStartupPhase(
                    "main_actor_startup_handoff",
                    startedAt: mainActorPhaseStartedAt,
                    metadata: ["gemini_supervisor_created": "yes"]
                )

                self.recoveryTask = Task.detached(priority: .background) {
                    let recoveryStartedAt = Date()
                    _ = try? CodexSessionStoreRecoveryService.run(
                        databasePath: databasePath,
                        sessionsRootPath: sessionsRootPath,
                        config: .startup
                    )
                    TokenmonAppBehaviorLogger.notice(
                        category: "recovery",
                        event: "codex_startup_recovery_completed",
                        metadata: [
                            "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: recoveryStartedAt),
                        ],
                        supportDirectoryPath: supportDirectoryPath
                    )
                }
            }

            TokenmonAppBehaviorLogger.notice(
                category: "startup",
                event: "startup_completed",
                metadata: [
                    "duration_ms": TokenmonAppBehaviorLogger.durationMillisecondsString(since: startupTaskStartedAt),
                ],
                supportDirectoryPath: supportDirectoryPath
            )
            await MainActor.run {
                if TokenmonBuildInfo.current.buildConfiguration == .release,
                   TokenmonInstalledAppBundleSupport.isInstalledAppBundle(),
                   self.menuModel.shouldAutoPresentOnboarding {
                    self.showOnboardingWindow(entrypoint: "startup")
                    TokenmonAppBehaviorLogger.notice(
                        category: "startup",
                        event: "first_run_onboarding_presented",
                        supportDirectoryPath: supportDirectoryPath
                    )
                }
                self.menuModel.emitAppOpenedAnalyticsIfNeeded()
            }
        }
    }

    private func runStartupWindowAutomationIfRequested(
        processInfo: ProcessInfo = .processInfo
    ) {
        let environment = processInfo.environment
        let arguments = processInfo.arguments
        let shouldOpenSettings = arguments.contains("--tokenmon-open-settings-on-launch")
            || Self.environmentFlag("TOKENMON_OPEN_SETTINGS_ON_LAUNCH", environment: environment)
        let shouldOpenDeveloper = arguments.contains("--tokenmon-open-developer-on-launch")
            || Self.environmentFlag("TOKENMON_OPEN_DEVELOPER_ON_LAUNCH", environment: environment)
        let shouldOpenOnboarding = arguments.contains("--tokenmon-open-onboarding-on-launch")
            || Self.environmentFlag("TOKENMON_OPEN_ONBOARDING_ON_LAUNCH", environment: environment)
        let shouldOpenPopover = arguments.contains("--tokenmon-open-popover-on-launch")
            || Self.environmentFlag("TOKENMON_OPEN_POPOVER_ON_LAUNCH", environment: environment)
        let shouldOpenRewardArchive = arguments.contains("--tokenmon-open-reward-archive-on-launch")
            || Self.environmentFlag("TOKENMON_OPEN_REWARD_ARCHIVE_ON_LAUNCH", environment: environment)

        guard shouldOpenSettings || shouldOpenDeveloper || shouldOpenOnboarding || shouldOpenPopover || shouldOpenRewardArchive else {
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else {
                return
            }

            if shouldOpenSettings {
                self.showSettings(pane: .general)
            }
            if shouldOpenDeveloper {
                self.showDeveloperWindow()
            }
            if shouldOpenOnboarding {
                self.showOnboardingWindow(entrypoint: "automation")
            }
            if shouldOpenPopover {
                self.showPopover()
            }
            if shouldOpenRewardArchive {
                self.showRewardArchiveWindow()
            }
        }
    }

    private static func environmentFlag(
        _ key: String,
        environment: [String: String]
    ) -> Bool {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(rawValue)
    }

    func stop() {
        TokenmonAppBehaviorLogger.notice(
            category: "app",
            event: "app_controller_stopped",
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        startupTask?.cancel()
        startupTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        cursorSyncTask?.cancel()
        cursorSyncTask = nil
        claudeTranscriptLiveObserver?.stop()
        claudeTranscriptLiveObserver = nil
        codexSessionStoreObserver?.stop()
        codexSessionStoreObserver = nil
        antigravityLocalRPCObserver?.stop()
        antigravityLocalRPCObserver = nil
        clearOnboardingWindow(closeWindow: true)
        if let supervisor = geminiSupervisor {
            Task { @MainActor in
                await supervisor.stop()
            }
        }
        geminiSupervisor = nil
        try? TokenmonDatabaseManager(path: menuModel.currentDatabasePath).clearLiveGameplayStartedAt()
        statusItemController.stop()
    }

    func showDexWindow(selecting speciesID: String? = nil) {
        if let speciesID {
            menuModel.requestDexNavigation(to: speciesID)
        }
        showCollectionWindow(section: .dex, entrypoint: "dex_window")
    }

    func showRewardArchiveWindow() {
        showCollectionWindow(section: .rewards, entrypoint: "reward_archive_window")
    }

    private func showCollectionWindow(
        section: TokenmonCollectionSection,
        entrypoint: String
    ) {
        collectionNavigationState.show(section)
        switch section {
        case .dex:
            analyticsTracker.captureSurfaceOpened(surface: .dex, entrypoint: entrypoint, settingsPane: nil)
            menuModel.surfaceOpened(.dex, entrypoint: "collection_window", emitAnalytics: false)
        case .rewards:
            analyticsTracker.captureSurfaceOpened(surface: .raid, entrypoint: entrypoint, settingsPane: nil)
            menuModel.surfaceOpened(.raid, entrypoint: "collection_window", emitAnalytics: false)
        }

        if collectionWindowController == nil {
            collectionWindowController = TokenmonHostingWindowController(
                title: TokenmonL10n.string("window.title.collection"),
                defaultSize: NSSize(width: tokenmonCollectionIdealWidth, height: tokenmonCollectionIdealHeight),
                minSize: NSSize(width: tokenmonCollectionMinimumWidth, height: tokenmonCollectionMinimumHeight),
                autosaveName: "TokenmonCollectionWindowV3",
                rootView: AnyView(
                    TokenmonCollectionPanel(
                        model: menuModel,
                        navigation: collectionNavigationState
                    )
                )
            )
            collectionWindowController?.window?.titleVisibility = .hidden
            collectionWindowController?.window?.contentMinSize = NSSize(
                width: tokenmonCollectionMinimumWidth,
                height: tokenmonCollectionMinimumHeight
            )
        }
        collectionWindowController?.show()
    }

    func showSettings(pane: TokenmonSettingsPane) {
        menuModel.revealSettingsPane(pane)
        analyticsTracker.captureSurfaceOpened(surface: .settings, entrypoint: "window", settingsPane: pane)
        if settingsWindowController == nil {
            settingsWindowController = TokenmonHostingWindowController(
                title: TokenmonL10n.string("window.title.settings"),
                defaultSize: NSSize(width: 760, height: 560),
                autosaveName: "TokenmonSettingsWindow",
                rootView: AnyView(
                    TokenmonSettingsPanel(
                        model: menuModel,
                        appUpdater: appUpdater,
                        onOpenWelcomeGuide: { [weak self] in
                            self?.showOnboardingWindow(entrypoint: "settings")
                        }
                    )
                )
            )
        }
        settingsWindowController?.show()
    }

    func showOnboardingWindow(entrypoint: String = "manual") {
        clearOnboardingWindow(closeWindow: true)
        analyticsTracker.captureSurfaceOpened(surface: .onboarding, entrypoint: entrypoint, settingsPane: nil)

        let controller = TokenmonHostingWindowController(
            title: TokenmonL10n.string("window.title.welcome_guide"),
            defaultSize: NSSize(width: 660, height: 560),
            minSize: NSSize(width: 620, height: 500),
            autosaveName: "TokenmonOnboardingWindowV2",
            rootView: AnyView(
                TokenmonOnboardingPanel(
                    model: menuModel,
                    onPerformSetupAction: { [weak self] action in
                        self?.performOnboardingSetupAction(action)
                    },
                    onSkip: { [weak self] in
                        self?.dismissOnboarding(reason: "skip")
                    },
                    onFinish: { [weak self] in
                        self?.dismissOnboarding(reason: "finish")
                    }
                )
            )
        )

        onboardingWindowController = controller
        if let window = controller.window {
            onboardingWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleOnboardingWindowClosedByUser()
                }
            }
        }

        TokenmonAppBehaviorLogger.notice(
            category: "onboarding",
            event: "onboarding_window_shown",
            metadata: ["entrypoint": entrypoint],
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        controller.show()
    }

    func showDeveloperWindow() {
        guard TokenmonBuildInfo.current.developerToolsVisible else {
            return
        }
        analyticsTracker.captureSurfaceOpened(surface: .developer, entrypoint: "window", settingsPane: nil)
        if developerWindowController == nil {
            developerWindowController = TokenmonHostingWindowController(
                title: TokenmonL10n.string("window.title.developer_tools"),
                defaultSize: NSSize(width: 1040, height: 780),
                autosaveName: "TokenmonDeveloperWindow",
                rootView: AnyView(
                    TokenmonDeveloperPanel(model: menuModel)
                )
            )
        }
        developerWindowController?.show()
    }

    func showPopover(initialActiveTab: TokenmonPopoverTab = .now) {
        let controller = statusItemController
        controller.setPopoverRootView(
            makePopoverRootView(
                controller: controller,
                initialActiveTab: initialActiveTab
            )
        )
        controller.openPopover()
    }

    private func captureNotificationOpened(speciesID: String, encounterID: String) {
        let encounter: PersistedEncounterRecord?
        do {
            let database = try TokenmonDatabaseManager(path: menuModel.currentDatabasePath).open()
            encounter = try EncounterHistoryStore.fetchEncounter(database: database, encounterID: encounterID)
        } catch {
            encounter = nil
        }

        analyticsTracker.captureCaptureNotificationOpened(
            speciesID: speciesID,
            provider: encounter?.providerCode,
            field: encounter?.field,
            rarity: encounter?.rarity
        )
    }

    private func performOnboardingSetupAction(_ action: TokenmonSetupRecommendationAction) {
        switch action {
        case .enableLaunchAtLogin:
            menuModel.setLaunchAtLogin(true)
        case .openLoginItemsSettings:
            menuModel.openLoginItemsSettings()
        case .enableCaptureNotifications:
            menuModel.updateNotificationsEnabled(true)
        case .requestCaptureNotificationPermission:
            menuModel.requestCaptureNotificationPermission()
        case .openNotificationSettings:
            menuModel.openSystemNotificationSettings()
        }
    }

    private func dismissOnboarding(reason: String) {
        menuModel.markFirstRunOnboardingShown()
        TokenmonAppBehaviorLogger.notice(
            category: "onboarding",
            event: "onboarding_window_dismissed",
            metadata: ["reason": reason],
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        clearOnboardingWindow(closeWindow: true)
    }

    private func handleOnboardingWindowClosedByUser() {
        menuModel.markFirstRunOnboardingShown()
        TokenmonAppBehaviorLogger.notice(
            category: "onboarding",
            event: "onboarding_window_dismissed",
            metadata: ["reason": "window_close"],
            supportDirectoryPath: menuModel.supportDirectoryPath
        )
        clearOnboardingWindow(closeWindow: false)
    }

    private func clearOnboardingWindow(closeWindow: Bool) {
        if let observer = onboardingWindowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingWindowCloseObserver = nil
        }

        if closeWindow {
            onboardingWindowController?.close()
        }

        onboardingWindowController = nil
    }

    private func makePopoverRootView(
        controller: TokenmonStatusItemController,
        initialActiveTab: TokenmonPopoverTab = .now
    ) -> AnyView {
        AnyView(
            TokenmonPopoverContainer(
                model: menuModel,
                actions: TokenmonPopoverContainerActions(
                    openFullDex: { [weak controller] in
                        controller?.closePopover()
                        TokenmonAppController.shared.showDexWindow()
                    },
                    openRewardArchive: { [weak controller] in
                        controller?.closePopover()
                        TokenmonAppController.shared.showRewardArchiveWindow()
                    },
                    openSettings: { [weak controller] pane in
                        controller?.closePopover()
                        TokenmonAppController.shared.showSettings(pane: pane)
                    },
                    openDeveloperTools: TokenmonBuildInfo.current.developerToolsVisible
                        ? { [weak controller] in
                            controller?.closePopover()
                            TokenmonAppController.shared.showDeveloperWindow()
                        }
                        : nil,
                    quit: {
                        NSApp.terminate(nil)
                    },
                    selectSpecies: { [weak controller] capture in
                        controller?.closePopover()
                        TokenmonAppController.shared.showDexWindow(selecting: capture.speciesID)
                    }
                ),
                initialActiveTab: initialActiveTab
            )
        )
    }

}

enum TokenmonStatusItemShortcutMenuItem: Equatable {
    case popover(TokenmonPopoverTab)
    case dexWindow
    case settingsWindow
    case developerTools
    case quit
    case separator

    static func defaultItems(
        developerToolsVisible: Bool
    ) -> [TokenmonStatusItemShortcutMenuItem] {
        var items: [TokenmonStatusItemShortcutMenuItem] = [
            .popover(.now),
            .popover(.raid),
            .popover(.tokens),
            .popover(.stats),
            .separator,
            .dexWindow,
            .settingsWindow,
        ]

        if developerToolsVisible {
            items.append(.developerTools)
        }

        items.append(contentsOf: [
            .separator,
            .quit,
        ])

        return items
    }

    var title: String {
        switch self {
        case .popover(.now):
            return TokenmonL10n.string("popover.tab.now")
        case .popover(.raid):
            return TokenmonL10n.string("popover.tab.raid")
        case .popover(.tokens):
            return TokenmonL10n.string("popover.tab.tokens")
        case .popover(.stats):
            return TokenmonL10n.string("popover.tab.stats")
        case .popover(.dex):
            return TokenmonL10n.string("window.title.dex")
        case .dexWindow:
            return TokenmonL10n.string("window.title.collection")
        case .settingsWindow:
            return TokenmonL10n.string("window.title.settings")
        case .developerTools:
            return TokenmonL10n.string("window.title.developer_tools")
        case .quit:
            return TokenmonL10n.string("popover.action.quit")
        case .separator:
            return ""
        }
    }
}

struct TokenmonStatusItemRenderUpdateKey: Equatable {
    let context: TokenmonSceneContext
    let tick: Int
    let tooltip: String
    let width: Int
    let height: Int
    let scale: Int
    let debugOffsetX: Int
    let debugOffsetY: Int

    init(
        context: TokenmonSceneContext,
        tick: Int,
        tooltip: String,
        buttonBounds: NSRect,
        scaleFactor: CGFloat,
        debugOffset: CGSize
    ) {
        self.context = context
        self.tick = tick
        self.tooltip = tooltip
        self.width = Int(buttonBounds.width.rounded())
        self.height = Int(buttonBounds.height.rounded())
        self.scale = Int((scaleFactor * 100).rounded())
        self.debugOffsetX = Int((debugOffset.width * 100).rounded())
        self.debugOffsetY = Int((debugOffset.height * 100).rounded())
    }
}

struct TokenmonStatusItemRenderUpdateGate {
    private var lastAppliedKey: TokenmonStatusItemRenderUpdateKey?

    mutating func shouldApply(_ key: TokenmonStatusItemRenderUpdateKey, force: Bool = false) -> Bool {
        if force {
            lastAppliedKey = key
            return true
        }
        guard lastAppliedKey != key else {
            return false
        }
        lastAppliedKey = key
        return true
    }

    mutating func reset() {
        lastAppliedKey = nil
    }
}

@MainActor
final class TokenmonStatusItemController: NSObject {
    private let model: TokenmonMenuModel
    private let debugController: TokenmonSceneDebugController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let playbackController = TokenmonScenePlaybackController()
    private var timer: Timer?
    private var currentRenderInterval: TimeInterval?
    private var renderUpdateGate = TokenmonStatusItemRenderUpdateGate()

    init(model: TokenmonMenuModel, debugController: TokenmonSceneDebugController) {
        self.model = model
        self.debugController = debugController
        super.init()
    }

    func setPopoverRootView(_ rootView: AnyView) {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(
            width: TokenmonPopoverContainer.width,
            height: TokenmonPopoverContainer.height
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
        TokenmonAppAppearanceController.syncHostWindow(popover.contentViewController?.view.window)
    }

    func start() {
        guard timer == nil else {
            return
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.title = ""
            button.appearsDisabled = false
        }

        renderStatusItem(force: true)
        updateTimerIfNeeded(for: model.restingSceneContext.sceneState)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate()
        timer = nil
        currentRenderInterval = nil
        renderUpdateGate.reset()
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func openPopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown == false {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            TokenmonAppAppearanceController.syncHostWindow(popover.contentViewController?.view.window)
            popover.contentViewController?.view.window?.becomeKey()
        } else {
            popover.contentViewController?.view.window?.displayIfNeeded()
        }
    }

    func openPopoverForAutomation() {
        openPopover()
    }

    func updatePopoverRootViewForAutomation(_ rootView: AnyView) {
        let shouldReopen = popover.isShown
        if shouldReopen {
            popover.performClose(nil)
        }
        setPopoverRootView(rootView)
        if shouldReopen {
            openPopoverForAutomation()
        }
    }

    var popoverWindowForAutomation: NSWindow? {
        popover.contentViewController?.view.window
    }

    func refreshForAutomation() {
        renderStatusItem(force: true)
    }

    func captureStatusItemButtonImage() async -> CGImage? {
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen else {
            return nil
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)

        if let capturedImage = await Self.captureStatusItemRegion(buttonFrameOnScreen, screen: screen) {
            return capturedImage
        }
        button.displayIfNeeded()
        return Self.captureStatusItemButtonViewImage(button)
    }

    func captureStatusItemButtonImageForAutomation(timeout: TimeInterval = 2.0) -> CGImage? {
        var capturedImage: CGImage?
        var isComplete = false
        Task { @MainActor in
            capturedImage = await captureStatusItemButtonImage()
            isComplete = true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while isComplete == false && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return capturedImage
    }

    @objc private func handleSystemWake() {
        renderStatusItem(force: true)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if isSecondaryClick(NSApp.currentEvent) {
            showShortcutMenu(using: button)
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            openPopover()
        }
    }

    @objc private func openNowShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showPopover(initialActiveTab: .now)
    }

    @objc private func openRaidShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showPopover(initialActiveTab: .raid)
    }

    @objc private func openTokensShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showPopover(initialActiveTab: .tokens)
    }

    @objc private func openStatsShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showPopover(initialActiveTab: .stats)
    }

    @objc private func openDexShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showDexWindow()
    }

    @objc private func openSettingsShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showSettings(pane: .general)
    }

    @objc private func openDeveloperToolsShortcut(_ sender: Any?) {
        TokenmonAppController.shared.showDeveloperWindow()
    }

    @objc private func quitShortcut(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func renderStatusItem(force: Bool = false) {
        let now = Date()

        playbackController.updateRestingContext(model.restingSceneContext)
        let pendingAnimations = model.consumePendingMenuBarEncounterAnimations()
        if pendingAnimations.isEmpty == false {
            playbackController.enqueue(encounters: pendingAnimations)
        }
        let context = debugController.menuBarContext(default: playbackController.context(at: now))
        updateTimerIfNeeded(for: context.sceneState)
        model.updateDisplayedSceneContext(context)

        guard let button = statusItem.button else {
            return
        }

        let tooltip = model.menuPresentation.headline
        let debugOffset = debugController.statusOffset(for: context.fieldKind)
        let updateKey = TokenmonStatusItemRenderUpdateKey(
            context: context,
            tick: TokenmonSceneTiming.statusItemTick(for: context, at: now),
            tooltip: tooltip,
            buttonBounds: button.bounds,
            scaleFactor: NSScreen.main?.backingScaleFactor ?? 2,
            debugOffset: debugOffset
        )
        guard renderUpdateGate.shouldApply(updateKey, force: force) else {
            return
        }

        if let image = TokenmonStatusItemImageRenderer.render(
            context: context,
            at: now,
            buttonBounds: button.bounds,
            debugController: debugController
        ) {
            button.image = image
            statusItem.length = image.size.width
        }
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    private func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }

        return event.type == .rightMouseUp ||
            (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
    }

    private func showShortcutMenu(using button: NSStatusBarButton) {
        popover.performClose(nil)

        let menu = makeShortcutMenu()
        statusItem.menu = menu
        defer {
            statusItem.menu = nil
        }
        button.performClick(nil)
    }

    private func makeShortcutMenu() -> NSMenu {
        let menu = NSMenu()

        for item in TokenmonStatusItemShortcutMenuItem.defaultItems(
            developerToolsVisible: TokenmonBuildInfo.current.developerToolsVisible
        ) {
            switch item {
            case .separator:
                menu.addItem(.separator())
            default:
                let menuItem = NSMenuItem(
                    title: item.title,
                    action: shortcutSelector(for: item),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menu.addItem(menuItem)
            }
        }

        return menu
    }

    private func shortcutSelector(
        for item: TokenmonStatusItemShortcutMenuItem
    ) -> Selector {
        switch item {
        case .popover(.now):
            return #selector(openNowShortcut(_:))
        case .popover(.raid):
            return #selector(openRaidShortcut(_:))
        case .popover(.tokens):
            return #selector(openTokensShortcut(_:))
        case .popover(.stats):
            return #selector(openStatsShortcut(_:))
        case .popover(.dex), .dexWindow:
            return #selector(openDexShortcut(_:))
        case .settingsWindow:
            return #selector(openSettingsShortcut(_:))
        case .developerTools:
            return #selector(openDeveloperToolsShortcut(_:))
        case .quit:
            return #selector(quitShortcut(_:))
        case .separator:
            return #selector(quitShortcut(_:))
        }
    }

    private func updateTimerIfNeeded(for sceneState: TokenmonSceneState) {
        let desiredInterval = Self.renderInterval(for: sceneState)
        guard currentRenderInterval != desiredInterval else {
            return
        }

        timer?.invalidate()
        let timer = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderStatusItem()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentRenderInterval = desiredInterval
    }

    private static func renderInterval(for sceneState: TokenmonSceneState) -> TimeInterval {
        switch sceneState {
        case .idle, .unavailable:
            return 0.5
        case .exploring, .loading, .rustle, .settle:
            return 0.25
        case .alert, .spawn, .resolveSuccess, .resolveEscape:
            return 0.125
        }
    }

    @available(macOS 14.0, *)
    private static func captureStatusItemRegionWithScreenCaptureKit(
        _ region: CGRect,
        displayID: CGDirectDisplayID,
        scaleFactor: CGFloat
    ) async -> CGImage? {
        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region
            configuration.width = max(1, Int((region.width * scaleFactor).rounded()))
            configuration.height = max(1, Int((region.height * scaleFactor).rounded()))
            configuration.showsCursor = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }

    private static func captureStatusItemRegion(
        _ region: CGRect,
        screen: NSScreen
    ) async -> CGImage? {
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        if #available(macOS 14.0, *) {
            return await captureStatusItemRegionWithScreenCaptureKit(
                region,
                displayID: CGDirectDisplayID(displayNumber.uint32Value),
                scaleFactor: screen.backingScaleFactor
            )
        }

        return nil
    }

    private static func captureStatusItemButtonViewImage(_ button: NSStatusBarButton) -> CGImage? {
        let bounds = button.bounds
        guard let bitmap = button.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        button.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.cgImage
    }
}

@MainActor
final class TokenmonHostingWindowController: NSWindowController {
    private let preferredMinimumSize: NSSize

    init(
        title: String,
        defaultSize: NSSize,
        minSize: NSSize? = nil,
        autosaveName: String,
        rootView: AnyView
    ) {
        self.preferredMinimumSize = minSize ?? defaultSize
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let visibleFrame = NSScreen.main?.visibleFrame
        window.setContentSize(Self.fittedSize(defaultSize, visibleFrame: visibleFrame))
        window.minSize = Self.fittedSize(self.preferredMinimumSize, visibleFrame: visibleFrame)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName(autosaveName)
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        TokenmonAppAppearanceController.syncHostWindow(window)
        showWindow(nil)
        TokenmonAppAppearanceController.syncHostWindow(window)
        keepWindowInsideVisibleScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.keepWindowInsideVisibleScreen()
        }
    }

    private func keepWindowInsideVisibleScreen() {
        guard let window else { return }
        let visibleFrame = bestVisibleFrame(for: window.frame)
        window.minSize = Self.fittedSize(preferredMinimumSize, visibleFrame: visibleFrame)
        var frame = window.frame
        let maximumSize = Self.maximumWindowSize(for: visibleFrame)
        frame.size.width = min(frame.width, maximumSize.width)
        frame.size.height = min(frame.height, maximumSize.height)

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }

    private static func fittedSize(_ size: NSSize, visibleFrame: NSRect?) -> NSSize {
        guard let visibleFrame else { return size }
        let maximumSize = maximumWindowSize(for: visibleFrame)
        return NSSize(
            width: min(size.width, maximumSize.width),
            height: min(size.height, maximumSize.height)
        )
    }

    private static func maximumWindowSize(for visibleFrame: NSRect) -> NSSize {
        NSSize(
            width: max(320, visibleFrame.width),
            height: max(320, visibleFrame.height)
        )
    }

    private func bestVisibleFrame(for frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        if let screen = screens.first(where: { $0.visibleFrame.intersects(frame) }) {
            return screen.visibleFrame
        }
        let frameCenter = NSPoint(x: frame.midX, y: frame.midY)
        if let nearest = screens.min(by: { lhs, rhs in
            squaredDistance(from: frameCenter, to: lhs.visibleFrame.center) <
                squaredDistance(from: frameCenter, to: rhs.visibleFrame.center)
        }) {
            return nearest.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? frame
    }

    private func squaredDistance(from point: NSPoint, to other: NSPoint) -> CGFloat {
        let dx = point.x - other.x
        let dy = point.y - other.y
        return (dx * dx) + (dy * dy)
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

enum TokenmonStatusItemImageRenderer {
    private struct RenderCacheKey: Hashable {
        let sceneState: String
        let fieldKind: String
        let fieldState: String
        let effectState: String
        let wildState: String
        let wildAssetKey: String?
        let showsFieldBackplate: Bool
        let tick: Int
        let width: Int
        let height: Int
        let scale: Int
        let debugOffsetX: Int
        let debugOffsetY: Int
    }

    private struct LayoutMetrics {
        let layout: TokenmonSceneLayout
        let imageSize: NSSize

        static func resolved(buttonBounds: NSRect) -> LayoutMetrics {
            let layout = TokenmonSceneLayout.statusStrip(forThickness: buttonBounds.height)

            return LayoutMetrics(
                layout: layout,
                imageSize: NSSize(width: layout.canvasSize.width, height: layout.canvasSize.height)
            )
        }
    }

    @MainActor private static var lastRenderKey: RenderCacheKey?
    @MainActor private static var lastRenderedImage: NSImage?

    @MainActor
    static func render(
        context: TokenmonSceneContext,
        at date: Date,
        buttonBounds: NSRect = NSRect(x: 0, y: 0, width: 44, height: NSStatusBar.system.thickness),
        debugController: TokenmonSceneDebugController = .shared
    ) -> NSImage? {
        let tick = TokenmonSceneTiming.statusItemTick(for: context, at: date)
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2
        let metrics = LayoutMetrics.resolved(buttonBounds: buttonBounds)
        let debugOffset = debugController.statusOffset(for: context.fieldKind)
        let cacheKey = RenderCacheKey(
            sceneState: context.sceneState.rawValue,
            fieldKind: context.fieldKind.rawValue,
            fieldState: context.fieldState.rawValue,
            effectState: context.effectState.rawValue,
            wildState: context.wildState.rawValue,
            wildAssetKey: context.wildAssetKey,
            showsFieldBackplate: context.showsFieldBackplate,
            tick: tick,
            width: Int(metrics.imageSize.width.rounded()),
            height: Int(metrics.imageSize.height.rounded()),
            scale: Int((scaleFactor * 100).rounded()),
            debugOffsetX: Int((debugOffset.width * 100).rounded()),
            debugOffsetY: Int((debugOffset.height * 100).rounded())
        )

        if cacheKey == lastRenderKey, let lastRenderedImage {
            return lastRenderedImage
        }

        let renderedImage: NSImage? = autoreleasepool {
            let renderer = ImageRenderer(
                content: TokenmonSceneCanvas(context: context, tick: tick, layout: metrics.layout)
                    .offset(
                        x: debugOffset.width,
                        y: debugOffset.height
                    )
                    .frame(
                        width: metrics.imageSize.width,
                        height: metrics.imageSize.height,
                        alignment: .topLeading
                    )
                    .background(Color.clear)
            )
            renderer.scale = scaleFactor
            renderer.proposedSize = ProposedViewSize(metrics.imageSize)
            return renderer.nsImage
        }

        guard let image = renderedImage else {
            return nil
        }
        image.size = metrics.imageSize
        lastRenderKey = cacheKey
        lastRenderedImage = image
        return image
    }
}

@MainActor
final class TokenmonScenePlaybackController {
    private struct TimedContext {
        let context: TokenmonSceneContext
        let duration: TimeInterval
    }

    private var restingContext = TokenmonSceneContext(
        sceneState: .idle,
        fieldKind: .grassland,
        fieldState: .calm,
        effectState: .none,
        wildState: .hidden
    )
    private var queuedSequences: [[TimedContext]] = []
    private var activeSequence: [TimedContext] = []
    private var activeIndex = 0
    private var phaseStartTime: Date?

    func updateRestingContext(_ restingContext: TokenmonSceneContext) {
        self.restingContext = restingContext
    }

    func enqueue(encounters: [RecentEncounterSummary]) {
        guard encounters.isEmpty == false else {
            return
        }

        for encounter in encounters.sorted(by: { $0.encounterSequence < $1.encounterSequence }) {
            let compact = queuedSequences.count >= 5
            queuedSequences.append(sequence(for: encounter, compact: compact))
        }
    }

    func context(at now: Date = Date()) -> TokenmonSceneContext {
        advance(now: now)

        guard activeSequence.isEmpty == false else {
            return restingContext
        }

        return activeSequence[activeIndex].context
    }

    private func advance(now: Date) {
        while true {
            guard activeSequence.isEmpty == false else {
                if let nextSequence = queuedSequences.first {
                    queuedSequences.removeFirst()
                    activeSequence = nextSequence
                    activeIndex = 0
                    phaseStartTime = now
                    continue
                }
                phaseStartTime = nil
                return
            }

            guard let phaseStartTime else {
                self.phaseStartTime = now
                return
            }

            let phaseDuration = activeSequence[activeIndex].duration
            guard now.timeIntervalSince(phaseStartTime) >= phaseDuration else {
                return
            }

            activeIndex += 1
            if activeIndex >= activeSequence.count {
                activeSequence.removeAll()
                activeIndex = 0
                self.phaseStartTime = nil
            } else {
                self.phaseStartTime = phaseStartTime.addingTimeInterval(phaseDuration)
            }
        }
    }

    private func sequence(
        for encounter: RecentEncounterSummary,
        compact: Bool
    ) -> [TimedContext] {
        let showsFieldBackplate = restingContext.showsFieldBackplate
        let resolveState: TokenmonSceneContext
        if encounter.outcome == EncounterOutcome.captured {
            resolveState = TokenmonSceneContext(
                sceneState: .resolveSuccess,
                fieldKind: .init(fieldType: encounter.field),
                fieldState: .settle,
                effectState: .captureSnap,
                wildState: .captured,
                wildAssetKey: encounter.assetKey,
                showsFieldBackplate: showsFieldBackplate
            )
        } else {
            resolveState = TokenmonSceneContext(
                sceneState: .resolveEscape,
                fieldKind: .init(fieldType: encounter.field),
                fieldState: .settle,
                effectState: .escapeDash,
                wildState: .escaped,
                wildAssetKey: encounter.assetKey,
                showsFieldBackplate: showsFieldBackplate
            )
        }

        let alertDuration = compact ? 0.16 : 0.26
        let spawnDuration = compact ? 0.26 : 0.40
        let resolveDuration = compact ? 0.42 : 0.60
        let settleDuration = compact ? 0.20 : 0.32

        return [
            TimedContext(
                context: TokenmonSceneContext(
                    sceneState: .alert,
                    fieldKind: .init(fieldType: encounter.field),
                    fieldState: .rustle,
                    effectState: .alert,
                    wildState: .hidden,
                    showsFieldBackplate: showsFieldBackplate
                ),
                duration: alertDuration
            ),
            TimedContext(
                context: TokenmonSceneContext(
                    sceneState: .spawn,
                    fieldKind: .init(fieldType: encounter.field),
                    fieldState: .rustle,
                    effectState: .none,
                    wildState: .spawning,
                    wildAssetKey: encounter.assetKey,
                    showsFieldBackplate: showsFieldBackplate
                ),
                duration: spawnDuration
            ),
            TimedContext(
                context: resolveState,
                duration: resolveDuration
            ),
            TimedContext(
                context: TokenmonSceneContext(
                    sceneState: .settle,
                    fieldKind: .init(fieldType: encounter.field),
                    fieldState: .settle,
                    effectState: .none,
                    wildState: .hidden,
                    showsFieldBackplate: showsFieldBackplate
                ),
                duration: settleDuration
            ),
        ]
    }
}
