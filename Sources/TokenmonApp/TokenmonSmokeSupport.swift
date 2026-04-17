import AppKit
import ImageIO
import ScreenCaptureKit
import SwiftUI
import TokenmonPersistence
import UniformTypeIdentifiers

private func tokenmonSceneContext(
    _ context: TokenmonSceneContext,
    applying settings: AppSettings
) -> TokenmonSceneContext {
    TokenmonSceneContext(
        sceneState: context.sceneState,
        fieldKind: context.fieldKind,
        fieldState: context.fieldState,
        effectState: context.effectState,
        wildState: context.wildState,
        wildAssetKey: context.wildAssetKey,
        showsFieldBackplate: settings.fieldBackplateEnabled
    )
}

enum TokenmonAppSmokeTest {
    static func runIfRequested(arguments: [String]) throws -> String? {
        guard arguments.contains("--smoke-test") else {
            return nil
        }

        let databasePath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        TokenmonInboxMonitor(databasePath: databasePath).performInitialScan()
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        var settings = try databaseManager.appSettings()

        if let value = boolOptionValue("--smoke-notifications-enabled", in: arguments) {
            settings.notificationsEnabled = value
        }
        if let value = boolOptionValue("--smoke-provider-status-visibility", in: arguments) {
            settings.providerStatusVisibility = value
        }
        if let value = boolOptionValue("--smoke-field-backplate-enabled", in: arguments) {
            settings.fieldBackplateEnabled = value
        }
        try databaseManager.saveAppSettings(settings)

        let summary = try databaseManager.currentRunSummary()
        let latestEncounter = try databaseManager.recentEncounterSummaries(limit: 1).first
        let seenEntries = try databaseManager.dexSeenSummaries()
        let capturedEntries = try databaseManager.dexCapturedSummaries()
        let providerHealth = try databaseManager.providerHealthSummaries()
        let launchState = TokenmonLaunchAtLoginController.snapshot()
        let sceneContext = tokenmonSceneContext(
            TokenmonSceneContextBuilder.context(summary: summary, latestEncounter: latestEncounter),
            applying: settings
        )

        return """
        smoke_test: ok
        animation_placeholder: field_effect_scene
        status_item_host: appkit_nsstatusitem
        status_item_animation: playback_queue
        scene_state: \(sceneContext.sceneState.rawValue)
        field_state: \(sceneContext.fieldState.rawValue)
        overlay_state: \(sceneContext.effectState.rawValue)
        wild_state: \(sceneContext.wildState.rawValue)
        provider_sessions: \(summary.providerSessions)
        usage_samples: \(summary.usageSamples)
        tokens_since_last_encounter: \(summary.tokensSinceLastEncounter)
        next_encounter_threshold_tokens: \(summary.nextEncounterThresholdTokens)
        total_encounters: \(summary.totalEncounters)
        seen_species: \(seenEntries.count)
        captured_species: \(capturedEntries.count)
        notifications_enabled: \(settings.notificationsEnabled)
        provider_status_visibility: \(settings.providerStatusVisibility)
        field_backplate_enabled: \(settings.fieldBackplateEnabled)
        provider_status_entries_visible: \(settings.providerStatusVisibility ? providerHealth.count : 0)
        launch_at_login_supported: \(launchState.isSupported)
        launch_at_login_effective: \(launchState.isEnabled)
        latest_encounter: \(latestEncounter?.speciesName ?? "none")
        """
    }

    static func sceneContext(
        summary: CurrentRunSummary,
        latestEncounter: RecentEncounterSummary?
    ) -> TokenmonSceneContext {
        TokenmonSceneContextBuilder.context(summary: summary, latestEncounter: latestEncounter)
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

    private static func boolOptionValue(_ flag: String, in arguments: [String]) -> Bool? {
        guard let rawValue = optionValue(flag, in: arguments) else {
            return nil
        }

        switch rawValue {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
}

@MainActor
enum TokenmonStatusStripScreenshotRenderer {
    static func runIfRequested(arguments: [String]) throws -> String? {
        guard arguments.contains("--render-menubar-strip-screenshots") else {
            return nil
        }

        let databasePath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        guard let outputDirectory = optionValue("--out-dir", in: arguments) else {
            throw ScreenshotRenderError.missingOutputDirectory
        }

        TokenmonInboxMonitor(databasePath: databasePath).performInitialScan()
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        let summary = try databaseManager.currentRunSummary()
        let latestEncounter = try databaseManager.recentEncounterSummaries(limit: 1).first
        let settings = try databaseManager.appSettings()

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )

        let liveContext = tokenmonSceneContext(
            TokenmonSceneContextBuilder.context(
                summary: summary,
                latestEncounter: latestEncounter
            ),
            applying: settings
        )
        let idleContext = tokenmonSceneContext(
            TokenmonSceneContext(
                sceneState: .idle,
                fieldKind: .grassland,
                fieldState: .calm,
                effectState: .none,
                wildState: .hidden
            ),
            applying: settings
        )
        let exploringContext = tokenmonSceneContext(
            TokenmonSceneContext(
                sceneState: .exploring,
                fieldKind: .grassland,
                fieldState: .exploring,
                effectState: .none,
                wildState: .hidden
            ),
            applying: settings
        )
        let resolveContext = latestEncounter.map {
            tokenmonSceneContext(
                $0.outcome == .captured
                    ? TokenmonSceneContext(
                        sceneState: .resolveSuccess,
                        fieldKind: .init(fieldType: $0.field),
                        fieldState: .settle,
                        effectState: .captureSnap,
                        wildState: .captured
                    )
                    : TokenmonSceneContext(
                        sceneState: .resolveEscape,
                        fieldKind: .init(fieldType: $0.field),
                        fieldState: .settle,
                        effectState: .escapeDash,
                        wildState: .escaped
                    ),
                applying: settings
            )
        } ?? liveContext

        let liveURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menubar-live.png")
        let idleURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menubar-idle.png")
        let exploringURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menubar-exploring.png")
        let resolveURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menubar-resolve.png")
        let fieldMatrixURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menubar-field-matrix.png")
        let effectMatrixURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menubar-effect-matrix.png")

        try renderStrip(context: liveContext, label: "Live", to: liveURL)
        try renderStrip(context: idleContext, label: "Idle", to: idleURL)
        try renderStrip(context: exploringContext, label: "Exploring", to: exploringURL)
        try renderStrip(context: resolveContext, label: "Resolve", to: resolveURL)
        try renderView(
            TokenmonMenubarFieldMatrixScreenshotView(),
            to: fieldMatrixURL
        )
        try renderView(
            TokenmonMenubarEffectMatrixScreenshotView(),
            to: effectMatrixURL
        )

        return """
        menubar_strip_screenshots: ok
        live: \(liveURL.path)
        idle: \(idleURL.path)
        exploring: \(exploringURL.path)
        resolve: \(resolveURL.path)
        field_matrix: \(fieldMatrixURL.path)
        effect_matrix: \(effectMatrixURL.path)
        """
    }

    private static func renderStrip(
        context: TokenmonSceneContext,
        label: String,
        to url: URL
    ) throws {
        let tick = TokenmonSceneTiming.tick(for: context, at: Date())
        let view = HStack(spacing: 10) {
            TokenmonSceneCanvas(context: context, tick: tick)
                .padding(.leading, 8)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.75))
            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.91, green: 0.93, blue: 0.96),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )

        try renderView(view, to: url)
    }

    private static func renderView<V: View>(_ view: V, to url: URL) throws {
        try renderScreenshotView(view, to: url)
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
}

@MainActor
enum TokenmonFieldPreviewSheetRenderer {
    static func runIfRequested(arguments: [String]) throws -> String? {
        guard arguments.contains("--render-field-preview-sheet") else {
            return nil
        }

        guard let outputDirectory = optionValue("--out-dir", in: arguments) else {
            throw ScreenshotRenderError.missingOutputDirectory
        }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )

        let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("field-previews.png")
        let view = TokenmonFieldPreviewSheet()
            .frame(width: 1220)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotRenderError.renderFailed(outputURL.path)
        }

        try pngData.write(to: outputURL)

        return """
        field_preview_sheet: ok
        output: \(outputURL.path)
        """
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
}

@MainActor
enum TokenmonActualPopoverScreenshotRenderer {
    static func runIfRequested(arguments: [String]) throws -> String? {
        guard arguments.contains("--render-actual-popover-screenshot") else {
            return nil
        }

        let databasePath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        guard let outputDirectory = optionValue("--out-dir", in: arguments) else {
            throw ScreenshotRenderError.missingOutputDirectory
        }
        let fileName = optionValue("--filename", in: arguments) ?? "actual-popover.png"

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )

        let model = makeScreenshotMenuModel(databasePath: databasePath)
        waitForInitialRefresh(of: model)
        TokenmonAppAppearanceController.apply(model.appSettings.appearancePreference)
        model.surfaceOpened(.now, entrypoint: "actual_popover_capture", refresh: true, emitAnalytics: false)
        waitForInitialRefresh(of: model)
        let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent(fileName)
        try captureHostedWindowRootView(
            actualPopoverRootView(model: model),
            size: NSSize(width: 360, height: 480),
            to: outputURL
        )

        return """
        actual_popover_screenshot: ok
        popover_capture_mode: actual_window
        output: \(outputURL.path)
        """
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
}

private struct TokenmonMenubarFieldScenario: Identifiable {
    let label: String
    let sceneState: TokenmonSceneState
    let fieldState: TokenmonFieldState
    let effectState: TokenmonEffectState

    var id: String { label }

    static let matrixScenarios: [TokenmonMenubarFieldScenario] = [
        TokenmonMenubarFieldScenario(
            label: "Calm",
            sceneState: .idle,
            fieldState: .calm,
            effectState: .none
        ),
        TokenmonMenubarFieldScenario(
            label: "Exploring",
            sceneState: .exploring,
            fieldState: .exploring,
            effectState: .none
        ),
        TokenmonMenubarFieldScenario(
            label: "Rustle",
            sceneState: .rustle,
            fieldState: .rustle,
            effectState: .none
        ),
        TokenmonMenubarFieldScenario(
            label: "Settle",
            sceneState: .settle,
            fieldState: .settle,
            effectState: .none
        ),
    ]

    static let effectScenarios: [TokenmonMenubarFieldScenario] = [
        TokenmonMenubarFieldScenario(
            label: "None",
            sceneState: .idle,
            fieldState: .calm,
            effectState: .none
        ),
        TokenmonMenubarFieldScenario(
            label: "Alert",
            sceneState: .alert,
            fieldState: .rustle,
            effectState: .alert
        ),
        TokenmonMenubarFieldScenario(
            label: "Capture",
            sceneState: .resolveSuccess,
            fieldState: .settle,
            effectState: .captureSnap
        ),
        TokenmonMenubarFieldScenario(
            label: "Escape",
            sceneState: .resolveEscape,
            fieldState: .settle,
            effectState: .escapeDash
        ),
    ]
}

private struct TokenmonPreviewStrip: View {
    let context: TokenmonSceneContext
    let scale: CGFloat

    var body: some View {
        let layout = TokenmonSceneLayout.statusStrip
        TokenmonSceneCanvas(context: context, tick: 3)
            .frame(
                width: layout.canvasSize.width,
                height: layout.canvasSize.height,
                alignment: .topLeading
            )
            .scaleEffect(scale, anchor: .topLeading)
            .frame(
                width: layout.canvasSize.width * scale,
                height: layout.canvasSize.height * scale,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct TokenmonStatusBarStripPreview: View {
    let context: TokenmonSceneContext

    var body: some View {
        HStack(spacing: 10) {
            TokenmonSceneCanvas(context: context, tick: 3)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
        .frame(width: 176, height: 28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.91, green: 0.93, blue: 0.96),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct TokenmonPreviewEvidenceCell: View {
    let context: TokenmonSceneContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TokenmonStatusBarStripPreview(context: context)
            TokenmonPreviewStrip(context: context, scale: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenmonFieldPreviewSheet: View {
    private let fields: [TokenmonSceneFieldKind] = [.grassland, .ice, .coast, .sky]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tokenmon Field Preview Sheet")
                    .font(.title2.weight(.bold))
                Text("Menu bar field readability at the 44x22 status strip contract.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TokenmonMenubarFieldMatrixView()
            TokenmonMenubarEffectMatrixView()
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct TokenmonMenubarFieldMatrixScreenshotView: View {
    var body: some View {
        TokenmonMenubarFieldMatrixView()
            .padding(24)
            .background(Color(nsColor: .underPageBackgroundColor))
            .frame(width: 1460)
    }
}

private struct TokenmonMenubarFieldMatrixView: View {
    private let fields: [TokenmonSceneFieldKind] = [.grassland, .ice, .coast, .sky]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text("Field")
                    .font(.caption.weight(.semibold))
                    .frame(width: 100, alignment: .leading)
                ForEach(TokenmonMenubarFieldScenario.matrixScenarios) { scenario in
                    Text(scenario.label)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(fields, id: \.rawValue) { field in
                HStack(alignment: .top, spacing: 16) {
                    Text(field.previewTitle)
                        .font(.headline)
                        .frame(width: 100, alignment: .leading)

                    ForEach(TokenmonMenubarFieldScenario.matrixScenarios) { scenario in
                        TokenmonPreviewEvidenceCell(
                                context: TokenmonSceneContext(
                                    sceneState: scenario.sceneState,
                                    fieldKind: field,
                                    fieldState: scenario.fieldState,
                                    effectState: scenario.effectState,
                                    wildState: .hidden,
                                    wildAssetKey: nil
                                )
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            }
        }
    }
}

private struct TokenmonMenubarEffectMatrixScreenshotView: View {
    var body: some View {
        TokenmonMenubarEffectMatrixView()
            .padding(24)
            .background(Color(nsColor: .underPageBackgroundColor))
            .frame(width: 1460)
    }
}

private struct TokenmonMenubarEffectMatrixView: View {
    private let fields: [TokenmonSceneFieldKind] = [.grassland, .ice, .coast, .sky]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tokenmon Effect Matrix")
                    .font(.title3.weight(.bold))
                Text("Verify that none, alert, capture, and escape effects stay centered in the field stage and read clearly across every field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Text("Field")
                    .font(.caption.weight(.semibold))
                    .frame(width: 100, alignment: .leading)
                ForEach(TokenmonMenubarFieldScenario.effectScenarios) { scenario in
                    Text(scenario.label)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(fields, id: \.rawValue) { field in
                HStack(alignment: .top, spacing: 16) {
                    Text(field.previewTitle)
                        .font(.headline)
                        .frame(width: 100, alignment: .leading)

                    ForEach(TokenmonMenubarFieldScenario.effectScenarios) { scenario in
                        TokenmonPreviewStrip(
                            context: TokenmonSceneContext(
                                sceneState: scenario.sceneState,
                                fieldKind: field,
                                fieldState: scenario.fieldState,
                                effectState: scenario.effectState,
                                wildState: .hidden,
                                wildAssetKey: nil
                            ),
                            scale: 4
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

@MainActor
enum TokenmonReadmeScreenshotRenderer {
    private enum MenuBarCaptureOutcome {
        case captured
        case skipped(String)
    }

    private struct MenuBarFrame {
        let sceneState: TokenmonSceneState
        let fieldState: TokenmonFieldState
        let effectState: TokenmonEffectState
        let wildState: TokenmonWildState
        let tick: Int
        let delay: Double
    }

    static func runIfRequested(arguments: [String]) throws -> String? {
        guard arguments.contains("--capture-readme-media") || arguments.contains("--render-readme-screenshots") else {
            return nil
        }

        let allowMenuBarSkip = arguments.contains("--allow-menu-bar-skip")
        let databasePath = optionValue("--db", in: arguments) ?? TokenmonDatabaseManager.defaultPath()
        guard let outputDirectory = optionValue("--out-dir", in: arguments) else {
            throw ScreenshotRenderError.missingOutputDirectory
        }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )

        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        let model = makeScreenshotMenuModel(databasePath: databasePath)
        let appUpdater = TokenmonAppUpdater()
        waitForInitialRefresh(of: model)
        model.hydrateRuntimeSnapshotForCapture()
        model.hydrateInsightsSnapshotForCapture()
        TokenmonAppAppearanceController.apply(model.appSettings.appearancePreference)

        let heroURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menu-hero.gif")
        let menuURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("menu-overview.png")
        let nowTabURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("now-tab.png")
        let tokensTabURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("tokens-tab.png")
        let statsTabURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("stats-tab.png")
        let dexURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("seen-dex.png")
        let settingsURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("settings.png")

        let popoverCaptureMode = try captureReadmePopoverScreenshots(
            model: model,
            outputs: [
                (.now, menuURL),
                (.now, nowTabURL),
                (.tokens, tokensTabURL),
                (.stats, statsTabURL),
            ],
            allowHostedFallback: allowMenuBarSkip
        )
        model.hydrateInsightsSnapshotForCapture()
        if let firstDexSpeciesID = try databaseManager.dexEntrySummaries().first?.speciesID {
            model.requestDexNavigation(to: firstDexSpeciesID)
        }
        try captureHostedWindowRootView(
            AnyView(TokenmonDexPanel(model: model)),
            size: NSSize(width: 1120, height: 980),
            captureWholeWindow: true,
            to: dexURL
        )
        model.surfaceOpened(.settings, entrypoint: "readme_capture", refresh: true, emitAnalytics: false)
        waitForInitialRefresh(of: model)
        model.hydrateSnapshotsForCapture(scopes: [.diagnostics])
        model.overrideLaunchAtLoginStateForCapture(
            TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
            )
        )
        model.revealSettingsPane(.general)
        try captureHostedWindowRootView(
            AnyView(
                TokenmonSettingsPanel(
                    model: model,
                    appUpdater: appUpdater,
                    onOpenWelcomeGuide: {}
                )
            ),
            size: NSSize(width: 760, height: 760),
            captureWholeWindow: true,
            to: settingsURL
        )
        let latestEncounter = try databaseManager.recentEncounterSummaries(limit: 1).first
        let menuBarCaptureOutcome = try captureMenuBarHeroLoop(
            model: model,
            latestEncounter: latestEncounter,
            to: heroURL,
            allowSkip: allowMenuBarSkip
        )

        var outputLines = [
            "readme_screenshots: ok",
            "capture_command: actual_ui",
            "popover_capture_mode: \(popoverCaptureMode)",
            "now_load_error: \(model.loadError ?? "none")",
            "now_summary_total_encounters: \(model.summary?.totalEncounters ?? -1)",
            "now_summary_total_captures: \(model.summary?.totalCaptures ?? -1)",
            "now_today_encounters: \(model.todayActivity?.encounterCount ?? -1)",
            "now_today_captures: \(model.todayActivity?.captureCount ?? -1)",
            "now_latest_encounter: \(model.latestEncounter?.speciesName ?? "none")",
            "now_tab: \(nowTabURL.path)",
            "tokens_tab: \(tokensTabURL.path)",
            "stats_tab: \(statsTabURL.path)",
            "dex_capture_mode: actual_window",
            "settings_capture_mode: actual_window",
            "menu_overview: \(menuURL.path)",
            "seen_dex: \(dexURL.path)",
            "settings: \(settingsURL.path)",
        ]

        switch menuBarCaptureOutcome {
        case .captured:
            outputLines.append("menu_bar_capture_mode: actual_status_item")
            outputLines.append("menu_bar_capture_status: captured")
            outputLines.append("hero_gif: \(heroURL.path)")
        case .skipped(let reason):
            outputLines.append("menu_bar_capture_mode: actual_status_item")
            outputLines.append("menu_bar_capture_status: skipped")
            outputLines.append("menu_bar_capture_reason: \(reason)")
        }

        return outputLines.joined(separator: "\n")
    }

    private static func captureMenuBarHeroLoop(
        model: TokenmonMenuModel,
        latestEncounter: RecentEncounterSummary?,
        to url: URL,
        allowSkip: Bool
    ) throws -> MenuBarCaptureOutcome {
        let debugController = TokenmonSceneDebugController.shared
        let statusController = TokenmonStatusItemController(model: model, debugController: debugController)
        statusController.setPopoverRootView(actualPopoverRootView(model: model))
        NSApp.setActivationPolicy(.accessory)
        statusController.start()
        defer {
            debugController.resetMenuBarPreview()
            statusController.stop()
        }

        guard waitForStatusItemWindow(using: statusController) else {
            if allowSkip {
                return .skipped("interactive status-item session unavailable")
            }
            throw ScreenshotRenderError.renderFailed("menu bar capture requires an interactive status item session")
        }

        let fieldKind = latestEncounter.map { TokenmonSceneFieldKind(fieldType: $0.field) } ?? model.restingSceneContext.fieldKind
        let wildAssetKey = latestEncounter?.assetKey ?? model.recentEncounterFeed.first?.assetKey
        let resolveWildState: TokenmonWildState = latestEncounter?.outcome == .escaped ? .escaped : .captured
        let resolveEffectState: TokenmonEffectState = latestEncounter?.outcome == .escaped ? .escapeDash : .captureSnap
        let resolveSceneState: TokenmonSceneState = latestEncounter?.outcome == .escaped ? .resolveEscape : .resolveSuccess
        let frames = menuBarFrames()

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw ScreenshotRenderError.renderFailed(url.path)
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ],
        ] as CFDictionary)

        for frame in frames {
            debugController.applyToMenuBar = true
            debugController.previewFieldKind = fieldKind
            debugController.previewSceneState = frame.sceneState == .resolveSuccess || frame.sceneState == .resolveEscape ? resolveSceneState : frame.sceneState
            debugController.previewFieldState = frame.fieldState
            debugController.previewEffectState = frame.sceneState == .resolveSuccess || frame.sceneState == .resolveEscape ? resolveEffectState : frame.effectState
            debugController.previewWildState = frame.sceneState == .resolveSuccess || frame.sceneState == .resolveEscape ? resolveWildState : frame.wildState
            debugController.previewWildAssetKey = frame.wildState == .hidden ? nil : wildAssetKey
            statusController.refreshForAutomation()
            pumpRunLoop(for: 0.08)

            guard let cgImage = statusController.captureStatusItemButtonImage() else {
                if allowSkip {
                    try? FileManager.default.removeItem(at: url)
                    return .skipped("actual status-item capture unavailable in this session")
                }
                throw ScreenshotRenderError.renderFailed("failed to capture on-screen NSStatusItem button")
            }

            CGImageDestinationAddImage(destination, cgImage, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.delay,
                ],
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotRenderError.renderFailed(url.path)
        }

        return .captured
    }

    private static func menuBarFrames() -> [MenuBarFrame] {
        [
            MenuBarFrame(sceneState: .exploring, fieldState: .exploring, effectState: .none, wildState: .hidden, tick: 0, delay: 0.14),
            MenuBarFrame(sceneState: .exploring, fieldState: .exploring, effectState: .none, wildState: .hidden, tick: 1, delay: 0.14),
            MenuBarFrame(sceneState: .exploring, fieldState: .exploring, effectState: .none, wildState: .hidden, tick: 2, delay: 0.14),
            MenuBarFrame(sceneState: .rustle, fieldState: .rustle, effectState: .none, wildState: .hidden, tick: 0, delay: 0.12),
            MenuBarFrame(sceneState: .rustle, fieldState: .rustle, effectState: .none, wildState: .hidden, tick: 1, delay: 0.12),
            MenuBarFrame(sceneState: .spawn, fieldState: .rustle, effectState: .alert, wildState: .spawning, tick: 0, delay: 0.10),
            MenuBarFrame(sceneState: .spawn, fieldState: .rustle, effectState: .alert, wildState: .spawning, tick: 1, delay: 0.10),
            MenuBarFrame(sceneState: .spawn, fieldState: .rustle, effectState: .alert, wildState: .spawning, tick: 2, delay: 0.10),
            MenuBarFrame(sceneState: .resolveSuccess, fieldState: .settle, effectState: .captureSnap, wildState: .captured, tick: 0, delay: 0.16),
            MenuBarFrame(sceneState: .resolveSuccess, fieldState: .settle, effectState: .captureSnap, wildState: .captured, tick: 1, delay: 0.16),
            MenuBarFrame(sceneState: .resolveSuccess, fieldState: .settle, effectState: .captureSnap, wildState: .captured, tick: 2, delay: 0.16),
        ]
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
}

@MainActor
private func makeScreenshotMenuModel(databasePath: String) -> TokenmonMenuModel {
    TokenmonMenuModel(
        databasePath: databasePath,
        launchAtLoginStateProvider: {
            TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
            )
        }
    )
}

@MainActor
private func renderScreenshotView<V: View>(_ view: V, to url: URL) throws {
    guard let cgImage = renderScreenshotCGImage(view) else {
        throw ScreenshotRenderError.renderFailed(url.path)
    }

    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw ScreenshotRenderError.renderFailed(url.path)
    }

    try pngData.write(to: url)
}

@MainActor
private func renderScreenshotCGImage<V: View>(_ view: V) -> CGImage? {
    let styledView = view
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .background(Color(nsColor: .windowBackgroundColor))

    let renderer = ImageRenderer(content: styledView)
    renderer.scale = 2

    if let cgImage = renderer.cgImage {
        return cgImage
    }

    guard let image = renderer.nsImage else {
        return nil
    }

    var proposedRect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
}

@MainActor
private func renderScreenshotNSImage<V: View>(_ view: V) -> NSImage? {
    let styledView = view
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .background(Color(nsColor: .windowBackgroundColor))

    let renderer = ImageRenderer(content: styledView)
    renderer.scale = 2
    return renderer.nsImage
}

private enum ScreenshotRenderError: Error, LocalizedError {
    case missingOutputDirectory
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingOutputDirectory:
            return "missing required --out-dir <path> for screenshot rendering"
        case .renderFailed(let path):
            return "failed to render screenshot to \(path)"
        }
    }
}

@MainActor
private func waitForInitialRefresh(of model: TokenmonMenuModel, timeout: TimeInterval = 2.0) {
    let semaphore = DispatchSemaphore(value: 0)
    Task { @MainActor in
        await model.waitForRefreshToFinish()
        semaphore.signal()
    }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if semaphore.wait(timeout: .now()) == .success {
            return
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private func pumpRunLoop(for duration: TimeInterval) {
    let end = Date().addingTimeInterval(duration)
    while Date() < end {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private func actualPopoverRootView(model: TokenmonMenuModel) -> AnyView {
    AnyView(
        TokenmonPopoverContainer(
            model: model,
            actions: TokenmonPopoverContainerActions(
                openFullDex: {},
                openSettings: { _ in },
                openDeveloperTools: nil,
                quit: {},
                selectSpecies: { _ in }
            )
        )
        .frame(width: 360, height: 480, alignment: .topLeading)
        .tokenmonPreferredColorScheme(model.appSettings.appearancePreference)
        .background(Color(nsColor: .windowBackgroundColor))
    )
}

@MainActor
private func actualPopoverRootView(
    model: TokenmonMenuModel,
    initialActiveTab: TokenmonPopoverTab
) -> AnyView {
    AnyView(
        TokenmonPopoverContainer(
            model: model,
            actions: TokenmonPopoverContainerActions(
                openFullDex: {},
                openSettings: { _ in },
                openDeveloperTools: nil,
                quit: {},
                selectSpecies: { _ in }
            ),
            initialActiveTab: initialActiveTab
        )
        .frame(width: 360, height: 480, alignment: .topLeading)
        .tokenmonPreferredColorScheme(model.appSettings.appearancePreference)
        .background(Color(nsColor: .windowBackgroundColor))
    )
}

@MainActor
private func captureReadmePopoverScreenshots(
    model: TokenmonMenuModel,
    outputs: [(tab: TokenmonPopoverTab, url: URL)],
    allowHostedFallback: Bool
) throws -> String {
    for output in outputs {
        if output.tab == .now {
            model.hydrateRuntimeSnapshotForCapture()
            model.updateDisplayedSceneContext(model.liveSceneContext)
        } else {
            model.hydrateInsightsSnapshotForCapture()
        }

        try captureHostedWindowRootView(
            actualPopoverRootView(model: model, initialActiveTab: output.tab),
            size: NSSize(width: 360, height: 480),
            captureWholeWindow: true,
            styleMask: [.borderless],
            to: output.url
        )
    }

    return allowHostedFallback ? "hosted_borderless_window" : "hosted_borderless_window"
}

@MainActor
private func captureHostedWindowRootView(
    _ rootView: AnyView,
    size: NSSize,
    captureWholeWindow: Bool = false,
    styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable],
    cropRectInPoints: CGRect? = nil,
    to url: URL
) throws {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: styleMask,
        backing: .buffered,
        defer: false
    )
    let hostingController = NSHostingController(rootView: rootView)
    window.contentViewController = hostingController
    let isBorderless = styleMask == [.borderless]
    window.backgroundColor = isBorderless ? .clear : NSColor.windowBackgroundColor
    window.isOpaque = !isBorderless
    window.hasShadow = true
    window.level = .normal
    window.alphaValue = 1
    window.ignoresMouseEvents = true
    window.setContentSize(size)
    TokenmonAppAppearanceController.syncHostWindow(window)
    window.setFrameOrigin(NSPoint(x: 64, y: 64))
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.displayIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    pumpRunLoop(for: 0.35)

    if captureWholeWindow, captureWindowViaSystemScreencapture(windowNumber: window.windowNumber, to: url) {
        window.orderOut(nil)
        return
    }

    if let screen = window.screen,
       let contentView = window.contentView {
        let contentRectInWindow = contentView.convert(contentView.bounds, to: nil)
        let contentRectOnScreen = window.convertToScreen(contentRectInWindow)
        if let cgImage = captureScreenRegion(contentRectOnScreen, screen: screen) {
        let outputImage = cropCGImage(
            cgImage,
            cropRectInPoints: cropRectInPoints,
            logicalSize: size
        ) ?? cgImage
        let bitmap = NSBitmapImageRep(cgImage: outputImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            window.orderOut(nil)
            throw ScreenshotRenderError.renderFailed(url.path)
        }
        try pngData.write(to: url)
        window.orderOut(nil)
        return
        }
    }

    guard let contentView = window.contentView else {
        window.orderOut(nil)
        throw ScreenshotRenderError.renderFailed(url.path)
    }

    try captureNSView(contentView, cropRectInPoints: cropRectInPoints, logicalSize: size, to: url)
    window.orderOut(nil)
}

@MainActor
private func captureWholeWindow(_ window: NSWindow, to url: URL) throws {
    window.displayIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    pumpRunLoop(for: 0.2)

    if captureWindowViaSystemScreencapture(windowNumber: window.windowNumber, to: url) {
        return
    }

    if let screen = window.screen,
       let cgImage = captureScreenRegion(window.frame, screen: screen) {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotRenderError.renderFailed(url.path)
        }
        try pngData.write(to: url)
        return
    }

    guard let contentView = window.contentView else {
        throw ScreenshotRenderError.renderFailed(url.path)
    }
    try captureNSView(contentView, cropRectInPoints: nil, logicalSize: contentView.bounds.size, to: url)
}

private func captureWindowViaSystemScreencapture(windowNumber: Int, to url: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(windowNumber)", url.path]

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return false
    }

    return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
}

@MainActor
private func captureNSView(
    _ view: NSView,
    cropRectInPoints: CGRect?,
    logicalSize: NSSize,
    to url: URL
) throws {
    let bounds = view.bounds
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
        throw ScreenshotRenderError.renderFailed(url.path)
    }

    view.cacheDisplay(in: bounds, to: bitmap)
    guard let cgImage = bitmap.cgImage else {
        throw ScreenshotRenderError.renderFailed(url.path)
    }
    let outputImage = cropCGImage(
        cgImage,
        cropRectInPoints: cropRectInPoints,
        logicalSize: logicalSize
    ) ?? cgImage
    let outputBitmap = NSBitmapImageRep(cgImage: outputImage)
    guard let pngData = outputBitmap.representation(using: .png, properties: [:]) else {
        throw ScreenshotRenderError.renderFailed(url.path)
    }

    try pngData.write(to: url)
}

private func cropCGImage(
    _ cgImage: CGImage,
    cropRectInPoints: CGRect?,
    logicalSize: NSSize
) -> CGImage? {
    guard let cropRectInPoints else {
        return nil
    }

    let scaleX = CGFloat(cgImage.width) / max(logicalSize.width, 1)
    let scaleY = CGFloat(cgImage.height) / max(logicalSize.height, 1)
    let rect = CGRect(
        x: cropRectInPoints.origin.x * scaleX,
        y: cropRectInPoints.origin.y * scaleY,
        width: cropRectInPoints.size.width * scaleX,
        height: cropRectInPoints.size.height * scaleY
    ).integral

    return cgImage.cropping(to: rect)
}

@MainActor
private func composeSidebarOverlay(
    contentURL: URL,
    overlayView: AnyView,
    overlaySize: NSSize,
    sidebarWidthPoints: CGFloat,
    contentTrimLeftPoints: CGFloat,
    outputURL: URL
) throws {
    guard let contentImage = NSImage(contentsOf: contentURL),
          let overlayImage = renderScreenshotNSImage(
            overlayView
                .frame(width: overlaySize.width, height: overlaySize.height, alignment: .topLeading)
          )
    else {
        throw ScreenshotRenderError.renderFailed(outputURL.path)
    }

    contentImage.size = overlaySize.width > 0 ? contentImage.size : contentImage.size
    overlayImage.size = overlaySize

    let outputSize = NSSize(
        width: contentImage.size.width - contentTrimLeftPoints + sidebarWidthPoints,
        height: contentImage.size.height
    )
    let composed = NSImage(size: outputSize)
    composed.lockFocus()
    let croppedContentRect = NSRect(
        x: contentTrimLeftPoints,
        y: 0,
        width: contentImage.size.width - contentTrimLeftPoints,
        height: contentImage.size.height
    )
    contentImage.draw(
        in: NSRect(
            x: sidebarWidthPoints,
            y: 0,
            width: croppedContentRect.width,
            height: croppedContentRect.height
        ),
        from: croppedContentRect,
        operation: .sourceOver,
        fraction: 1
    )

    let overlayRect = NSRect(
        x: 0,
        y: outputSize.height - overlaySize.height,
        width: sidebarWidthPoints,
        height: overlaySize.height
    )
    overlayImage.draw(
        in: overlayRect,
        from: NSRect(x: 0, y: 0, width: sidebarWidthPoints, height: overlaySize.height),
        operation: .sourceOver,
        fraction: 1
    )
    composed.unlockFocus()

    guard let tiffData = composed.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw ScreenshotRenderError.renderFailed(outputURL.path)
    }
    try pngData.write(to: outputURL)
    try? FileManager.default.removeItem(at: contentURL)
}

private struct TokenmonDexSidebarSnapshotView: View {
    @ObservedObject var model: TokenmonMenuModel

    private var entries: [DexEntrySummary] {
        model.dexEntries.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TokenmonL10n.string("window.title.dex"))
                .font(.headline)
            dexSidebarRow(TokenmonDexSidebarSelection.all, count: entries.count, selected: true)
            dexSidebarRow(
                TokenmonDexSidebarSelection.captured,
                count: entries.filter { $0.status == .captured }.count,
                selected: false
            )
            dexSidebarRow(
                TokenmonDexSidebarSelection.seenUncaptured,
                count: entries.filter { $0.status == .seenUncaptured }.count,
                selected: false
            )
            dexSidebarRow(
                TokenmonDexSidebarSelection.unknown,
                count: entries.filter { $0.status == .unknown }.count,
                selected: false
            )
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func dexSidebarRow(
        _ selection: TokenmonDexSidebarSelection,
        count: Int,
        selected: Bool
    ) -> some View {
        HStack {
            Label(selection.title, systemImage: selection.systemImage)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.secondary.opacity(0.16) : Color.clear)
        )
    }
}

private struct TokenmonSettingsSidebarSnapshotView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TokenmonSettingsPane.allCases, id: \.self) { pane in
                HStack {
                    Label(pane.title, systemImage: pane.systemImage)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pane == .general ? Color.secondary.opacity(0.16) : Color.clear)
                )
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TokenmonSettingsScreenshotShell: View {
    @ObservedObject var model: TokenmonMenuModel
    @ObservedObject var appUpdater: TokenmonAppUpdater
    let launchAtLoginState: TokenmonLaunchAtLoginState

    var body: some View {
        HStack(spacing: 0) {
            TokenmonSettingsSidebarSnapshotView()
                .frame(width: 176, alignment: .topLeading)

            Divider()

            TokenmonGeneralSettingsPane(
                appSettings: model.appSettings,
                launchAtLoginState: launchAtLoginState,
                notificationAuthorizationState: model.notificationAuthorizationState,
                appUpdater: appUpdater,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError,
                onSetLaunchAtLogin: { _ in },
                onOpenLoginItemsSettings: {},
                onUpdateAppearancePreference: { _ in },
                onUpdateLanguagePreference: { _ in },
                onUpdateProviderStatusVisibility: { _ in },
                onUpdateFieldBackplateEnabled: { _ in },
                onUpdateNotificationsEnabled: { _ in },
                onRequestNotificationPermission: {},
                onUpdateUpdateNotificationsEnabled: { _ in },
                onUpdateUsageAnalyticsEnabled: { _ in },
                onOpenSystemNotificationSettings: {},
                onOpenWelcomeGuide: {}
            )
            .frame(maxWidth: 584, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
private func waitForStatusItemWindow(
    using controller: TokenmonStatusItemController,
    timeout: TimeInterval = 2.0
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        controller.refreshForAutomation()
        if controller.captureStatusItemButtonImage() != nil {
            return true
        }
        pumpRunLoop(for: 0.05)
    }
    return false
}

@MainActor
private func waitForPopoverWindow(
    using controller: TokenmonStatusItemController,
    timeout: TimeInterval = 2.0
) -> NSWindow? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let window = controller.popoverWindowForAutomation {
            return window
        }
        if let fallbackWindow = NSApp.windows.first(where: { window in
            window.isVisible && abs(window.frame.width - 360) < 4 && abs(window.frame.height - 480) < 4
        }) {
            return fallbackWindow
        }
        pumpRunLoop(for: 0.05)
    }
    return nil
}

@MainActor
private func captureScreenRegion(_ region: CGRect, screen: NSScreen) -> CGImage? {
    guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return nil
    }

    let semaphore = DispatchSemaphore(value: 0)
    var capturedImage: CGImage?
    Task {
        capturedImage = await captureScreenRegionAsync(
            region,
            displayID: CGDirectDisplayID(displayNumber.uint32Value),
            scaleFactor: screen.backingScaleFactor
        )
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 2.0)
    return capturedImage
}

@available(macOS 14.0, *)
private func captureScreenRegionWithScreenCaptureKit(
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

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    } catch {
        return nil
    }
}

private func captureScreenRegionAsync(
    _ region: CGRect,
    displayID: CGDirectDisplayID,
    scaleFactor: CGFloat
) async -> CGImage? {
    if #available(macOS 14.0, *) {
        return await captureScreenRegionWithScreenCaptureKit(region, displayID: displayID, scaleFactor: scaleFactor)
    }
    return nil
}
