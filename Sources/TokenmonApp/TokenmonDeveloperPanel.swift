import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TokenmonDomain
import TokenmonPersistence

private enum TokenmonDeveloperPathSelection: Hashable {
    case transcript
    case executable(ProviderCode)
    case configuration(ProviderCode)
}

private enum TokenmonDeveloperPane: String, CaseIterable, Hashable {
    case quickFix
    case qaControls
    case diagnostics
    case recovery
    case visual

    var title: String {
        switch self {
        case .quickFix:
            return TokenmonL10n.string("developer.pane.quick_fix.title")
        case .qaControls:
            return TokenmonL10n.string("developer.pane.qa_controls.title")
        case .diagnostics:
            return TokenmonL10n.string("developer.pane.diagnostics.title")
        case .recovery:
            return TokenmonL10n.string("developer.pane.recovery.title")
        case .visual:
            return TokenmonL10n.string("developer.pane.visual.title")
        }
    }

    var subtitle: String {
        switch self {
        case .quickFix:
            return TokenmonL10n.string("developer.pane.quick_fix.subtitle")
        case .qaControls:
            return TokenmonL10n.string("developer.pane.qa_controls.subtitle")
        case .diagnostics:
            return TokenmonL10n.string("developer.pane.diagnostics.subtitle")
        case .recovery:
            return TokenmonL10n.string("developer.pane.recovery.subtitle")
        case .visual:
            return TokenmonL10n.string("developer.pane.visual.subtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .quickFix:
            return "wrench.and.screwdriver"
        case .qaControls:
            return "slider.horizontal.3"
        case .diagnostics:
            return "waveform.path.ecg"
        case .recovery:
            return "arrow.clockwise.circle"
        case .visual:
            return "sparkles.rectangle.stack"
        }
    }
}

private struct TokenmonDeveloperConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let action: () -> Void
}

struct TokenmonDeveloperPanel: View {
    @ObservedObject var model: TokenmonMenuModel
    @ObservedObject private var adaptiveChromeController = TokenmonAdaptiveChromeController.shared

    @State private var selectedPane: TokenmonDeveloperPane = .quickFix
    @State private var backfillProvider: ProviderCode = .claude
    @State private var transcriptPath = ""
    @State private var sessionID = ""
    @State private var explorationTotalDraft = ""
    @State private var tokensSinceLastEncounterDraft = ""
    @State private var nextEncounterThresholdDraft = ""
    @State private var totalEncountersDraft = ""
    @State private var totalCapturesDraft = ""
    @State private var forgeProvider: ProviderCode = .codex
    @State private var forgeField: FieldType = .grassland
    @State private var forgeRarity: RarityTier = .common
    @State private var forgeOutcome: EncounterOutcome = .captured
    @State private var forgeSpeciesID = ""
    @State private var visualSpeciesID = ""
    @State private var draftsSeeded = false
    @State private var pendingConfirmation: TokenmonDeveloperConfirmation?
    @State private var pendingPathSelection: TokenmonDeveloperPathSelection?

    private let actionColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12),
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                ForEach(TokenmonDeveloperPane.allCases, id: \.self) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 188, idealWidth: 196)
        } detail: {
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            model.surfaceOpened(.developer)
            seedDraftsFromCurrentSummary()
            normalizeForgeSpecies()
            normalizeVisualSpecies()
        }
        .onChange(of: model.summary) { _, _ in
            if draftsSeeded == false {
                seedDraftsFromCurrentSummary()
            }
        }
        .onChange(of: forgeField) { _, _ in
            normalizeForgeSpecies()
        }
        .onChange(of: forgeRarity) { _, _ in
            normalizeForgeSpecies()
        }
        .onChange(of: model.dexEntries) { _, _ in
            normalizeVisualSpecies()
        }
        .alert(item: $pendingConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.confirmTitle)) {
                    confirmation.action()
                    seedDraftsFromCurrentSummary()
                },
                secondaryButton: .cancel()
            )
        }
        .fileImporter(
            isPresented: Binding(
                get: { pendingPathSelection != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingPathSelection = nil
                    }
                }
            ),
            allowedContentTypes: importerAllowedContentTypes
        ) { result in
            handleImporterResult(result)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selectedPane {
        case .quickFix:
            TokenmonDeveloperPaneContainer(
                pane: .quickFix,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError
            ) {
                quickFixContent
            }
        case .qaControls:
            TokenmonDeveloperPaneContainer(
                pane: .qaControls,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError
            ) {
                qaControlsContent
            }
        case .diagnostics:
            TokenmonDeveloperPaneContainer(
                pane: .diagnostics,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError
            ) {
                diagnosticsContent
            }
        case .recovery:
            TokenmonDeveloperPaneContainer(
                pane: .recovery,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError
            ) {
                recoveryContent
            }
        case .visual:
            TokenmonDeveloperPaneContainer(
                pane: .visual,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError
            ) {
                visualContent
            }
        }
    }

    private var quickFixContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.runtime_snapshot"), systemImage: "bolt.horizontal.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    TokenmonDeveloperMetricsGrid(metrics: quickFixMetrics)

                    if let latestEncounter = model.latestEncounter {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(TokenmonL10n.string("developer.latest_encounter"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(latestEncounter.speciesName) · \(latestEncounter.outcome.displayName)")
                                .font(.subheadline.weight(.medium))
                            Text("\(latestEncounter.rarity.displayName) • \(latestEncounter.field.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if model.loadError != nil {
                        Divider()
                        TokenmonDeveloperInfoRow(
                            title: TokenmonL10n.string("developer.app_load_error"),
                            value: model.loadError ?? TokenmonL10n.string("common.unknown"),
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .red
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.quick_actions"), systemImage: "sparkles") {
                TokenmonDeveloperActionGrid(columns: actionColumns) {
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("settings.providers.action.detect_again"),
                        subtitle: TokenmonL10n.string("developer.quick_action.detect_again"),
                        action: { model.redetectProviders() }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("common.refresh"),
                        subtitle: TokenmonL10n.string("developer.quick_action.refresh"),
                        action: { model.refresh(reason: .manual) }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.action.rescan_inbox"),
                        subtitle: TokenmonL10n.string("developer.quick_action.rescan_inbox"),
                        action: { model.rescanInbox() }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.action.reveal_database"),
                        subtitle: TokenmonL10n.string("developer.quick_action.reveal_database"),
                        action: { reveal(path: model.currentDatabasePath, isDirectory: false) }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.action.reveal_inbox"),
                        subtitle: TokenmonL10n.string("developer.quick_action.reveal_inbox"),
                        action: { reveal(path: model.inboxDirectoryPath, isDirectory: true) }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.action.reveal_support"),
                        subtitle: TokenmonL10n.string("developer.quick_action.reveal_support"),
                        action: { reveal(path: model.supportDirectoryPath, isDirectory: true) }
                    )
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.provider_repair"), systemImage: "switch.2") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(TokenmonL10n.string("developer.provider_repair.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(model.onboardingStatuses, id: \.provider) { status in
                        TokenmonDeveloperProviderCard(
                            status: status,
                            healthSummary: model.providerHealthSummaries.first(where: { $0.provider == status.provider }),
                            codexMode: model.providerInstallationPreferences.codexMode,
                            nextStep: model.providerHealthSummaries.first(where: { $0.provider == status.provider })
                                .map(model.nextStep(for:)) ?? "Monitor recent provider activity.",
                            onConnect: {
                                model.connectProvider(status.provider)
                            },
                            onChooseExecutable: {
                                pendingPathSelection = .executable(status.provider)
                            },
                            onChooseConfiguration: {
                                pendingPathSelection = .configuration(status.provider)
                            },
                            onResetToAuto: {
                                model.resetProviderOverrides(for: status.provider)
                            },
                            onRevealExecutable: {
                                if let path = status.executablePath {
                                    reveal(path: path, isDirectory: false)
                                }
                            },
                            onRevealConfiguration: {
                                reveal(path: status.configurationPath, isDirectory: true)
                            },
                            onSetCodexMode: { mode in
                                model.setCodexConnectionMode(mode)
                            }
                        )
                    }
                }
            }
        }
    }

    private var qaControlsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.chrome_preview"), systemImage: "macwindow.on.rectangle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TokenmonL10n.string("developer.chrome_preview.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(
                        TokenmonL10n.string("developer.chrome_preview.force_toggle"),
                        isOn: $adaptiveChromeController.forceCompatibilityChrome
                    )

                    TokenmonDeveloperInfoRow(
                        title: TokenmonL10n.string("developer.chrome_preview.current_mode_title"),
                        value: adaptiveChromeStatusText,
                        systemImage: adaptiveChromeController.shouldUseCompatibilityChrome ? "square.on.square.squareshape.controlhandles" : "sparkles.rectangle.stack",
                        tint: adaptiveChromeController.shouldUseCompatibilityChrome ? .orange : .green
                    )
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.scenario_presets"), systemImage: "rectangle.3.group") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TokenmonL10n.string("developer.scenario_presets.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        ForEach(TokenmonDeveloperScenarioPreset.allCases, id: \.self) { preset in
                            TokenmonDeveloperActionButton(
                                title: preset.title,
                                subtitle: preset.subtitle,
                                prominent: preset == .encounterReady,
                                action: {
                                    model.runScenarioPreset(preset)
                                    seedDraftsFromCurrentSummary()
                                }
                            )
                        }
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.resets"), systemImage: "trash") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TokenmonL10n.string("developer.resets.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.reset.gameplay.title"),
                            subtitle: TokenmonL10n.string("developer.reset.gameplay.subtitle"),
                            role: .destructive,
                            action: {
                                pendingConfirmation = TokenmonDeveloperConfirmation(
                                    title: TokenmonL10n.string("developer.reset.gameplay.confirm_title"),
                                    message: TokenmonL10n.string("developer.reset.gameplay.confirm_message"),
                                    confirmTitle: TokenmonL10n.string("developer.reset.gameplay.confirm_button"),
                                    action: { model.resetGameplayProgress() }
                                )
                            }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.reset.dex.title"),
                            subtitle: TokenmonL10n.string("developer.reset.dex.subtitle"),
                            role: .destructive,
                            action: {
                                pendingConfirmation = TokenmonDeveloperConfirmation(
                                    title: TokenmonL10n.string("developer.reset.dex.confirm_title"),
                                    message: TokenmonL10n.string("developer.reset.dex.confirm_message"),
                                    confirmTitle: TokenmonL10n.string("developer.reset.dex.confirm_button"),
                                    action: { model.resetDexProgress() }
                                )
                            }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.reset.encounter_history.title"),
                            subtitle: TokenmonL10n.string("developer.reset.encounter_history.subtitle"),
                            role: .destructive,
                            action: {
                                pendingConfirmation = TokenmonDeveloperConfirmation(
                                    title: TokenmonL10n.string("developer.reset.encounter_history.confirm_title"),
                                    message: TokenmonL10n.string("developer.reset.encounter_history.confirm_message"),
                                    confirmTitle: TokenmonL10n.string("developer.reset.encounter_history.confirm_button"),
                                    action: { model.resetEncounterHistory() }
                                )
                            }
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.encounter_forge"), systemImage: "sparkles") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TokenmonL10n.string("developer.encounter_forge.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Picker("Provider", selection: $forgeProvider) {
                            ForEach(ProviderCode.allCases, id: \.self) { provider in
                                Text(provider.displayName)
                                    .tag(provider)
                            }
                        }
                        Picker("Field", selection: $forgeField) {
                            ForEach(FieldType.allCases, id: \.self) { field in
                                Text(field.displayName)
                                    .tag(field)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Picker("Rarity", selection: $forgeRarity) {
                            ForEach(RarityTier.allCases, id: \.self) { rarity in
                                Text(rarity.displayName)
                                    .tag(rarity)
                            }
                        }
                        Picker("Outcome", selection: $forgeOutcome) {
                            ForEach(EncounterOutcome.allCases, id: \.self) { outcome in
                                Text(outcome.displayName)
                                    .tag(outcome)
                            }
                        }
                    }

                    Picker("Species", selection: $forgeSpeciesID) {
                        ForEach(forgeCandidateSpecies, id: \.id) { species in
                            Text(species.name)
                                .tag(species.id)
                        }
                    }
                    .disabled(forgeCandidateSpecies.isEmpty)

                    if let selectedSpecies = forgeSelectedSpecies {
                        TokenmonDeveloperInfoRow(
                            title: TokenmonL10n.string("developer.encounter_forge.selected_species"),
                            value: "\(selectedSpecies.name) · \(selectedSpecies.field.displayName) · \(selectedSpecies.rarity.displayName)",
                            systemImage: "pawprint.fill",
                            tint: .secondary
                        )
                    }

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.encounter_forge.forge_action_title"),
                            subtitle: TokenmonL10n.string("developer.encounter_forge.forge_action_subtitle"),
                            prominent: true,
                            disabled: forgeSelectedSpecies == nil,
                            action: {
                                guard let species = forgeSelectedSpecies else {
                                    return
                                }
                                model.forgeEncounter(
                                    provider: forgeProvider,
                                    field: forgeField,
                                    rarity: forgeRarity,
                                    speciesID: species.id,
                                    outcome: forgeOutcome
                                )
                                seedDraftsFromCurrentSummary()
                            }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.encounter_forge.preview_alert_title"),
                            subtitle: TokenmonL10n.string("developer.encounter_forge.preview_alert_subtitle"),
                            disabled: forgeSelectedSpecies == nil,
                            action: {
                                guard let species = forgeSelectedSpecies else {
                                    return
                                }
                                model.sendCaptureNotificationPreview(speciesID: species.id)
                            }
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.exploration_override"), systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 12) {
                    TokenmonDeveloperCurrentValueList(rows: explorationCurrentRows)

                    TokenmonDeveloperNumericField(
                        title: TokenmonL10n.string("developer.exploration.total_normalized_tokens"),
                        text: $explorationTotalDraft,
                        currentValue: model.summary.map { "\($0.totalNormalizedTokens)" } ?? TokenmonL10n.string("common.unavailable"),
                        helper: TokenmonL10n.string("developer.exploration.total_normalized_tokens_helper")
                    )
                    TokenmonDeveloperNumericField(
                        title: TokenmonL10n.string("developer.exploration.tokens_since_last_encounter"),
                        text: $tokensSinceLastEncounterDraft,
                        currentValue: model.summary.map { "\($0.tokensSinceLastEncounter)" } ?? TokenmonL10n.string("common.unavailable"),
                        helper: TokenmonL10n.string("developer.exploration.tokens_since_last_encounter_helper")
                    )
                    TokenmonDeveloperNumericField(
                        title: TokenmonL10n.string("developer.exploration.next_encounter_threshold"),
                        text: $nextEncounterThresholdDraft,
                        currentValue: model.summary.map { "\($0.nextEncounterThresholdTokens)" } ?? TokenmonL10n.string("common.unavailable"),
                        helper: TokenmonL10n.string("developer.exploration.next_encounter_threshold_helper")
                    )

                    if let explorationValidationMessage {
                        TokenmonDeveloperInlineValidation(message: explorationValidationMessage)
                    }

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.exploration.load_current_values_title"),
                            subtitle: TokenmonL10n.string("developer.exploration.load_current_values_subtitle"),
                            action: seedDraftsFromCurrentSummary
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.exploration.make_next_ready_title"),
                            subtitle: TokenmonL10n.string("developer.exploration.make_next_ready_subtitle"),
                            prominent: true,
                            action: {
                                model.makeNextEncounterReady()
                                seedDraftsFromCurrentSummary()
                            }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.exploration.apply_override_title"),
                            subtitle: TokenmonL10n.string("developer.exploration.apply_override_subtitle"),
                            prominent: true,
                            disabled: explorationOverrideValues == nil,
                            action: {
                                guard let values = explorationOverrideValues else {
                                    return
                                }
                                model.applyExplorationOverride(
                                    totalNormalizedTokens: values.totalNormalizedTokens,
                                    tokensSinceLastEncounter: values.tokensSinceLastEncounter,
                                    nextEncounterThresholdTokens: values.nextEncounterThresholdTokens
                                )
                                seedDraftsFromCurrentSummary()
                            }
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.totals_override"), systemImage: "sum") {
                VStack(alignment: .leading, spacing: 12) {
                    TokenmonDeveloperCurrentValueList(rows: totalsCurrentRows)

                    TokenmonDeveloperNumericField(
                        title: TokenmonL10n.string("developer.totals.total_encounters"),
                        text: $totalEncountersDraft,
                        currentValue: model.summary.map { "\($0.totalEncounters)" } ?? TokenmonL10n.string("common.unavailable"),
                        helper: TokenmonL10n.string("developer.totals.total_encounters_helper")
                    )
                    TokenmonDeveloperNumericField(
                        title: TokenmonL10n.string("developer.totals.total_captures"),
                        text: $totalCapturesDraft,
                        currentValue: model.summary.map { "\($0.totalCaptures)" } ?? TokenmonL10n.string("common.unavailable"),
                        helper: TokenmonL10n.string("developer.totals.total_captures_helper")
                    )

                    if let totalsValidationMessage {
                        TokenmonDeveloperInlineValidation(message: totalsValidationMessage)
                    }

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.totals.load_current_title"),
                            subtitle: TokenmonL10n.string("developer.totals.load_current_subtitle"),
                            action: seedDraftsFromCurrentSummary
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.totals.apply_override_title"),
                            subtitle: TokenmonL10n.string("developer.totals.apply_override_subtitle"),
                            prominent: true,
                            disabled: totalsOverrideValues == nil,
                            action: {
                                guard let values = totalsOverrideValues else {
                                    return
                                }
                                model.applyTotalsOverride(
                                    totalEncounters: values.totalEncounters,
                                    totalCaptures: values.totalCaptures
                                )
                                seedDraftsFromCurrentSummary()
                            }
                        )
                    }
                }
            }
        }
    }

    private var diagnosticsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.app_state"), systemImage: "bolt.horizontal.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    TokenmonDeveloperValueRow(label: "Database", value: model.currentDatabasePath)
                    TokenmonDeveloperValueRow(label: "Support", value: model.supportDirectoryPath)
                    TokenmonDeveloperValueRow(label: "Inbox", value: model.inboxDirectoryPath)
                    TokenmonDeveloperValueRow(label: "App Log", value: model.appLogFilePath)

                    if let databaseSummary = model.databaseSummary {
                        TokenmonDeveloperValueRow(
                            label: "Live Gameplay Boundary",
                            value: databaseSummary.liveGameplayStartedAt ?? "none"
                        )
                        Divider()
                        TokenmonDeveloperMetricsGrid(metrics: [
                            ("Providers", "\(databaseSummary.providers)"),
                            ("Sessions", "\(databaseSummary.providerSessions)"),
                            ("Ingest Events", "\(databaseSummary.providerIngestEvents)"),
                            ("Domain Events", "\(databaseSummary.domainEvents)"),
                            ("Species", "\(databaseSummary.species)"),
                        ])
                    }

                    if let loadError = model.loadError {
                        Divider()
                        TokenmonDeveloperInfoRow(
                            title: "App Load Error",
                            value: loadError,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .red
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: "Updater", systemImage: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    TokenmonDeveloperValueRow(
                        label: "Availability",
                        value: model.appUpdaterDiagnostics.isAvailable ? "available" : "unavailable"
                    )
                    TokenmonDeveloperValueRow(
                        label: "Feed",
                        value: model.appUpdaterDiagnostics.configuredFeedURL?.absoluteString ?? "none"
                    )
                    TokenmonDeveloperValueRow(
                        label: "Feed Source",
                        value: model.appUpdaterDiagnostics.feedURLSource?.developerDescription ?? "none"
                    )
                    TokenmonDeveloperValueRow(
                        label: "Signing Key Source",
                        value: model.appUpdaterDiagnostics.publicEDKeySource?.developerDescription ?? "none"
                    )
                    TokenmonDeveloperValueRow(
                        label: "Override File",
                        value: model.appUpdaterDiagnostics.overrideFilePath
                    )
                    TokenmonDeveloperValueRow(
                        label: "Custom Config Active",
                        value: model.appUpdaterDiagnostics.hasNonBundledConfiguration ? "yes" : "no"
                    )

                    if let reason = model.appUpdaterDiagnostics.unavailabilityReason {
                        TokenmonDeveloperInfoRow(
                            title: "Updater Issue",
                            value: String(describing: reason),
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange
                        )
                    }

                    if let overrideLoadErrorDescription = model.appUpdaterDiagnostics.overrideLoadErrorDescription {
                        TokenmonDeveloperInfoRow(
                            title: "Override Parse Error",
                            value: overrideLoadErrorDescription,
                            systemImage: "xmark.octagon.fill",
                            tint: .red
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.app_logs"), systemImage: "text.alignleft") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TokenmonL10n.string("developer.app_logs.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.app_logs.reload_title"),
                            subtitle: TokenmonL10n.string("developer.app_logs.reload_subtitle"),
                            action: { model.refresh(reason: .surfaceOpened(.developer)) }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.app_logs.reveal_log_file_title"),
                            subtitle: TokenmonL10n.string("developer.app_logs.reveal_log_file_subtitle"),
                            action: { reveal(path: model.appLogFilePath, isDirectory: false) }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.app_logs.reveal_logs_folder_title"),
                            subtitle: TokenmonL10n.string("developer.app_logs.reveal_logs_folder_subtitle"),
                            action: { reveal(path: model.logsDirectoryPath, isDirectory: true) }
                        )
                    }

                    if model.recentAppLogEntries.isEmpty {
                        TokenmonDeveloperInfoRow(
                            title: TokenmonL10n.string("developer.app_logs.recent_logs"),
                            value: TokenmonL10n.string("developer.app_logs.empty"),
                            systemImage: "tray",
                            tint: .secondary
                        )
                    } else {
                        ForEach(Array(model.recentAppLogEntries.suffix(40).enumerated().reversed()), id: \.offset) { _, entry in
                            TokenmonDeveloperAppLogRow(entry: entry)
                        }
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.provider_diagnostics"), systemImage: "waveform.path.ecg") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.providerHealthSummaries, id: \.provider) { summary in
                        TokenmonDeveloperDiagnosticCard(
                            summary: summary,
                            nextStep: model.nextStep(for: summary)
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.domain_event_timeline"), systemImage: "timeline.selection") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.recentDomainEventRecords.prefix(20).enumerated()), id: \.offset) { _, record in
                        TokenmonDeveloperDomainEventRow(record: record)
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.provider_sessions"), systemImage: "person.3.sequence") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.recentProviderSessionSummaries, id: \.providerSessionRowID) { session in
                        TokenmonDeveloperProviderSessionRow(session: session)
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.recent_ingest_events"), systemImage: "tray.full") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.recentProviderIngestEventSummaries, id: \.providerIngestEventID) { event in
                        TokenmonDeveloperIngestEventRow(event: event)
                    }
                }
            }
        }
    }

    private var recoveryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.maintenance"), systemImage: "wrench.and.screwdriver") {
                TokenmonDeveloperActionGrid(columns: actionColumns) {
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.maintenance.bootstrap_title"),
                        subtitle: TokenmonL10n.string("developer.maintenance.bootstrap_subtitle"),
                        action: { model.bootstrapAppState() }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.maintenance.reseed_species_title"),
                        subtitle: TokenmonL10n.string("developer.maintenance.reseed_species_subtitle"),
                        action: { model.reseedSpeciesCatalog() }
                    )
                    TokenmonDeveloperActionButton(
                        title: TokenmonL10n.string("developer.action.rescan_inbox"),
                        subtitle: TokenmonL10n.string("developer.maintenance.rescan_inbox_subtitle"),
                        action: { model.rescanInbox() }
                    )
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.transcript_backfill"), systemImage: "arrow.clockwise.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Provider", selection: $backfillProvider) {
                        ForEach(ProviderCode.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    TokenmonDeveloperPathField(
                        title: TokenmonL10n.string("developer.transcript_backfill.path_title"),
                        text: $transcriptPath,
                        browseTitle: TokenmonL10n.string("common.browse"),
                        onBrowse: {
                            pendingPathSelection = .transcript
                        }
                    )

                    TextField(TokenmonL10n.string("developer.transcript_backfill.optional_session_id"), text: $sessionID)
                        .textFieldStyle(.roundedBorder)

                    TokenmonDeveloperActionGrid(columns: actionColumns) {
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.transcript_backfill.run_title"),
                            subtitle: TokenmonL10n.string("developer.transcript_backfill.run_subtitle"),
                            prominent: true,
                            disabled: transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            action: {
                                model.runTranscriptBackfill(
                                    provider: backfillProvider,
                                    transcriptPath: transcriptPath,
                                    sessionID: sessionID
                                )
                            }
                        )
                        TokenmonDeveloperActionButton(
                            title: TokenmonL10n.string("developer.maintenance.database_title"),
                            subtitle: TokenmonL10n.string("developer.maintenance.database_subtitle"),
                            action: { model.performDatabaseMaintenance() }
                        )
                    }
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.recent_backfill_runs"), systemImage: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.recentBackfillRunSummaries.enumerated()), id: \.offset) { _, run in
                        TokenmonDeveloperBackfillRunRow(run: run)
                    }
                }
            }
        }
    }

    private var visualContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.visual_tools"), systemImage: "sparkles.rectangle.stack") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TokenmonL10n.string("developer.visual_tools.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TokenmonSceneDebugPanel(
                        embedded: true,
                        companionAssetKeysByField: visualCompanionAssetKeysByField
                    )
                }
            }

            TokenmonSettingsSectionCard(title: TokenmonL10n.string("developer.section.dex_art_inspector"), systemImage: "photo.stack") {
                if let entry = visualInspectorEntry {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Species", selection: $visualSpeciesID) {
                            ForEach(visualInspectorEntries, id: \.speciesID) { option in
                                Text(String(format: "#%03d %@", option.sortOrder, option.speciesName))
                                    .tag(option.speciesID)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack(spacing: 8) {
                            TokenmonDexStatusBadge(status: entry.status, compact: false)
                            TokenmonRarityBadge(rarity: entry.rarity, compact: false)
                            TokenmonFieldBadge(field: entry.field)
                        }

                        TokenmonDexSpriteInspectorSection(entry: entry)
                    }
                } else {
                    ContentUnavailableView(
                        TokenmonL10n.string("developer.dex_art_inspector.empty_title"),
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(TokenmonL10n.string("developer.dex_art_inspector.empty_description"))
                    )
                }
            }
        }
    }

    private var quickFixMetrics: [(String, String)] {
        [
            ("Tokens", model.summary.map { "\($0.totalNormalizedTokens)" } ?? "0"),
            ("Encounters", model.summary.map { "\($0.totalEncounters)" } ?? "0"),
            ("Captures", model.summary.map { "\($0.totalCaptures)" } ?? "0"),
            ("Seen Species", model.summary.map { "\($0.seenSpeciesCount)" } ?? "0"),
            ("Captured Species", model.summary.map { "\($0.capturedSpeciesCount)" } ?? "0"),
        ]
    }

    private var explorationCurrentRows: [(String, String)] {
        [
            ("Total Normalized Tokens", model.summary.map { "\($0.totalNormalizedTokens)" } ?? "Unavailable"),
            ("Tokens Since Last Encounter", model.summary.map { "\($0.tokensSinceLastEncounter)" } ?? "Unavailable"),
            ("Next Encounter Threshold", model.summary.map { "\($0.nextEncounterThresholdTokens)" } ?? "Unavailable"),
            ("Tokens Until Next Encounter", model.summary.map { "\($0.tokensUntilNextEncounter)" } ?? "Unavailable"),
        ]
    }

    private var totalsCurrentRows: [(String, String)] {
        [
            ("Total Encounters", model.summary.map { "\($0.totalEncounters)" } ?? "Unavailable"),
            ("Total Captures", model.summary.map { "\($0.totalCaptures)" } ?? "Unavailable"),
        ]
    }

    private var forgeCandidateSpecies: [SpeciesDefinition] {
        SpeciesCatalog.all.filter {
            $0.isActive && $0.field == forgeField && $0.rarity == forgeRarity
        }
    }

    private var visualInspectorEntries: [DexEntrySummary] {
        model.dexEntries
            .filter { $0.status != .unknown }
            .sorted { lhs, rhs in
                let lhsDate = TokenmonDexPresentation.latestActivityDate(for: lhs) ?? .distantPast
                let rhsDate = TokenmonDexPresentation.latestActivityDate(for: rhs) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var visualInspectorEntry: DexEntrySummary? {
        guard visualSpeciesID.isEmpty == false else {
            return visualInspectorEntries.first
        }
        return visualInspectorEntries.first(where: { $0.speciesID == visualSpeciesID }) ?? visualInspectorEntries.first
    }

    private var visualCompanionAssetKeysByField: [TokenmonSceneFieldKind: [String]] {
        let grouped = Dictionary(grouping: model.dexEntries.filter { $0.status == .captured }) { entry in
            TokenmonSceneFieldKind(fieldType: entry.field)
        }

        return grouped.mapValues { entries in
            let sorted = entries.sorted { lhs, rhs in
                if lhs.lastCapturedAt != rhs.lastCapturedAt {
                    return (lhs.lastCapturedAt ?? "") > (rhs.lastCapturedAt ?? "")
                }
                return lhs.speciesID < rhs.speciesID
            }
            let assetKeys = sorted.map(\.assetKey)
            return Array(NSOrderedSet(array: assetKeys)) as? [String] ?? assetKeys
        }
    }

    private var forgeSelectedSpecies: SpeciesDefinition? {
        forgeCandidateSpecies.first(where: { $0.id == forgeSpeciesID }) ?? forgeCandidateSpecies.first
    }

    private var explorationOverrideValues: (totalNormalizedTokens: Int64, tokensSinceLastEncounter: Int64, nextEncounterThresholdTokens: Int64)? {
        guard let totalNormalizedTokens = parseInt64(explorationTotalDraft),
              let tokensSinceLastEncounter = parseInt64(tokensSinceLastEncounterDraft),
              let nextEncounterThresholdTokens = parseInt64(nextEncounterThresholdDraft)
        else {
            return nil
        }

        guard totalNormalizedTokens >= 0,
              tokensSinceLastEncounter >= 0,
              nextEncounterThresholdTokens > 0,
              totalNormalizedTokens >= tokensSinceLastEncounter,
              tokensSinceLastEncounter < nextEncounterThresholdTokens
        else {
            return nil
        }

        return (totalNormalizedTokens, tokensSinceLastEncounter, nextEncounterThresholdTokens)
    }

    private var totalsOverrideValues: (totalEncounters: Int64, totalCaptures: Int64)? {
        guard let totalEncounters = parseInt64(totalEncountersDraft),
              let totalCaptures = parseInt64(totalCapturesDraft)
        else {
            return nil
        }

        guard totalEncounters >= 0,
              totalCaptures >= 0,
              totalCaptures <= totalEncounters
        else {
            return nil
        }

        return (totalEncounters, totalCaptures)
    }

    private var explorationValidationMessage: String? {
        if explorationTotalDraft.isEmpty && tokensSinceLastEncounterDraft.isEmpty && nextEncounterThresholdDraft.isEmpty {
            return nil
        }

        guard let totalNormalizedTokens = parseInt64(explorationTotalDraft),
              let tokensSinceLastEncounter = parseInt64(tokensSinceLastEncounterDraft),
              let nextEncounterThresholdTokens = parseInt64(nextEncounterThresholdDraft)
        else {
            return "Enter valid integer values for all three fields."
        }

        if totalNormalizedTokens < 0 || tokensSinceLastEncounter < 0 {
            return "Token values must be non-negative."
        }
        if nextEncounterThresholdTokens <= 0 {
            return "Next encounter threshold must be positive."
        }
        if totalNormalizedTokens < tokensSinceLastEncounter {
            return "Total normalized tokens must be at least tokens since last encounter."
        }
        if tokensSinceLastEncounter >= nextEncounterThresholdTokens {
            return "Tokens since last encounter must stay below the next encounter threshold."
        }

        return nil
    }

    private var totalsValidationMessage: String? {
        if totalEncountersDraft.isEmpty && totalCapturesDraft.isEmpty {
            return nil
        }

        guard let totalEncounters = parseInt64(totalEncountersDraft),
              let totalCaptures = parseInt64(totalCapturesDraft)
        else {
            return "Enter valid integer values for encounter totals."
        }

        if totalEncounters < 0 || totalCaptures < 0 {
            return "Totals must be non-negative."
        }
        if totalCaptures > totalEncounters {
            return "Total captures cannot exceed total encounters."
        }

        return nil
    }

    private func parseInt64(_ rawValue: String) -> Int64? {
        Int64(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func normalizeVisualSpecies() {
        let validIDs = Set(visualInspectorEntries.map(\.speciesID))
        if let first = visualInspectorEntries.first, validIDs.contains(visualSpeciesID) == false {
            visualSpeciesID = first.speciesID
        }
        if visualInspectorEntries.isEmpty {
            visualSpeciesID = ""
        }
    }

    private func seedDraftsFromCurrentSummary() {
        guard let summary = model.summary else {
            draftsSeeded = false
            return
        }

        explorationTotalDraft = "\(summary.totalNormalizedTokens)"
        tokensSinceLastEncounterDraft = "\(summary.tokensSinceLastEncounter)"
        nextEncounterThresholdDraft = "\(summary.nextEncounterThresholdTokens)"
        totalEncountersDraft = "\(summary.totalEncounters)"
        totalCapturesDraft = "\(summary.totalCaptures)"
        draftsSeeded = true
        normalizeForgeSpecies()
    }

    private func normalizeForgeSpecies() {
        if forgeCandidateSpecies.contains(where: { $0.id == forgeSpeciesID }) {
            return
        }
        forgeSpeciesID = forgeCandidateSpecies.first?.id ?? ""
    }

    private var importerAllowedContentTypes: [UTType] {
        switch pendingPathSelection {
        case .configuration(_):
            return TokenmonFileImportRequirement.directory.allowedContentTypes
        case .transcript, .executable(_), .none:
            return TokenmonFileImportRequirement.file.allowedContentTypes
        }
    }

    private func handleImporterResult(_ result: Result<URL, Error>) {
        let selection = pendingPathSelection
        pendingPathSelection = nil
        guard let selection else {
            return
        }

        switch selection {
        case .transcript:
            applyImportOutcome(
                TokenmonFileImportSupport.resolve(
                    result: result,
                    requirement: .file,
                    invalidSelectionMessage: "Choose a transcript file, not a folder."
                )
            ) { path in
                transcriptPath = path
            }
        case .executable(let provider):
            applyImportOutcome(
                TokenmonFileImportSupport.resolve(
                    result: result,
                    requirement: .file,
                    invalidSelectionMessage: "Choose an executable file, not a folder."
                )
            ) { path in
                model.setProviderExecutableOverride(path, for: provider)
            }
        case .configuration(let provider):
            applyImportOutcome(
                TokenmonFileImportSupport.resolve(
                    result: result,
                    requirement: .directory,
                    invalidSelectionMessage: "Choose a configuration folder."
                )
            ) { path in
                model.setProviderConfigurationOverride(path, for: provider)
            }
        }
    }

    private func applyImportOutcome(
        _ outcome: TokenmonFileImportOutcome,
        applyPath: (String) -> Void
    ) {
        switch outcome {
        case .imported(let path):
            applyPath(path)
        case .cancelled:
            return
        case .failure(let message):
            model.presentSettingsFeedback(message: nil, error: message)
        }
    }

    private var adaptiveChromeStatusText: String {
        if adaptiveChromeController.runtimeSupportsNativeGlass {
            if adaptiveChromeController.forceCompatibilityChrome {
                return TokenmonL10n.string("developer.chrome_preview.current_mode.compat")
            }

            return TokenmonL10n.string("developer.chrome_preview.current_mode.native")
        }

        return TokenmonL10n.string("developer.chrome_preview.current_mode.compat_required")
    }

    private func reveal(path: String, isDirectory: Bool) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path, isDirectory: isDirectory),
        ])
    }
}

private struct TokenmonDeveloperPaneContainer<Content: View>: View {
    let pane: TokenmonDeveloperPane
    let settingsMessage: String?
    let settingsError: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pane.title)
                            .font(.largeTitle.weight(.semibold))
                        Text(pane.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    TokenmonDeveloperBadge(title: "Internal Only", systemImage: "lock.shield")
                }

                TokenmonSettingsFeedbackSection(
                    settingsMessage: settingsMessage,
                    settingsError: settingsError
                )

                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct TokenmonDeveloperBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
    }
}

private struct TokenmonDeveloperActionGrid<Content: View>: View {
    let columns: [GridItem]
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            content()
        }
    }
}

private struct TokenmonDeveloperActionButton: View {
    let title: String
    let subtitle: String?
    var role: ButtonRole? = nil
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        if prominent {
            baseButton
                .tokenmonAdaptiveButtonStyle(.prominent, paddingMode: .labelProvided)
                .controlSize(.regular)
                .disabled(disabled)
        } else {
            baseButton
                .tokenmonAdaptiveButtonStyle(paddingMode: .labelProvided)
                .controlSize(.regular)
                .disabled(disabled)
        }
    }

    private var baseButton: some View {
        Button(role: role, action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(prominent ? Color.white.opacity(0.88) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

private struct TokenmonDeveloperMetricsGrid: View {
    let metrics: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.1)
                        .font(.title3.weight(.semibold))
                    Text(metric.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .tokenmonAdaptiveSurface(cornerRadius: 12)
            }
        }
    }
}

private struct TokenmonDeveloperValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private struct TokenmonDeveloperCurrentValueList: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Values")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.subheadline)
            }
        }
    }
}

private struct TokenmonDeveloperNumericField: View {
    let title: String
    @Binding var text: String
    let currentValue: String
    let helper: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
            Text("Current: \(currentValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(helper)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TokenmonDeveloperInlineValidation: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

private struct TokenmonDeveloperPathField: View {
    let title: String
    @Binding var text: String
    let browseTitle: String
    let onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            HStack {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                Button(browseTitle, action: onBrowse)
                    .tokenmonAdaptiveButtonStyle()
                    .controlSize(.small)
            }
        }
    }
}

private struct TokenmonDeveloperProviderCard: View {
    let status: TokenmonProviderOnboardingStatus
    let healthSummary: ProviderHealthSummary?
    let codexMode: CodexConnectionMode
    let nextStep: String
    let onConnect: () -> Void
    let onChooseExecutable: () -> Void
    let onChooseConfiguration: () -> Void
    let onResetToAuto: () -> Void
    let onRevealExecutable: () -> Void
    let onRevealConfiguration: () -> Void
    let onSetCodexMode: (CodexConnectionMode) -> Void

    private let actionColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.provider.displayName)
                        .font(.headline)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TokenmonDeveloperStateBadge(state: TokenmonSettingsPresentationBuilder.providerCardState(for: status))
            }

            Text(
                TokenmonSettingsPresentationBuilder.providerMetadataLine(
                    status: status,
                    healthSummary: healthSummary
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            TokenmonDeveloperInfoRow(
                title: "Next",
                value: nextStep,
                systemImage: "arrow.turn.down.right",
                tint: .secondary
            )

            if let lastObservedAt = healthSummary?.lastObservedAt {
                TokenmonDeveloperInfoRow(
                    title: "Observed",
                    value: lastObservedAt,
                    systemImage: "clock",
                    tint: .secondary
                )
            }

            if let lastError = healthSummary?.lastErrorSummary {
                TokenmonDeveloperInfoRow(
                    title: "Last Error",
                    value: lastError,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            if status.provider == .codex {
                Picker(
                    "Codex Mode",
                    selection: Binding(
                        get: { codexMode },
                        set: { newValue in
                            onSetCodexMode(newValue)
                        }
                    )
                ) {
                    ForEach(CodexConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Paths")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TokenmonDeveloperValueRow(label: "Executable", value: status.executablePath ?? "Not detected")
                TokenmonDeveloperValueRow(label: "Config", value: status.configurationPath)
            }

            TokenmonDeveloperActionGrid(columns: actionColumns) {
                if let actionTitle = status.actionTitle {
                    TokenmonDeveloperActionButton(
                        title: actionTitle,
                        subtitle: "Run the maintainer-owned connect or repair flow.",
                        prominent: true,
                        action: onConnect
                    )
                }

                TokenmonDeveloperActionButton(
                    title: "Choose Executable",
                    subtitle: "Point Tokenmon at a custom binary path.",
                    action: onChooseExecutable
                )
                TokenmonDeveloperActionButton(
                    title: "Choose Config Folder",
                    subtitle: "Point Tokenmon at a custom config folder.",
                    action: onChooseConfiguration
                )
                TokenmonDeveloperActionButton(
                    title: "Reveal Executable",
                    subtitle: "Show the current executable path in Finder.",
                    disabled: status.executablePath == nil,
                    action: onRevealExecutable
                )
                TokenmonDeveloperActionButton(
                    title: "Reveal Config Folder",
                    subtitle: "Show the current configuration folder in Finder.",
                    action: onRevealConfiguration
                )

                if status.usesCustomExecutablePath || status.usesCustomConfigurationPath {
                    TokenmonDeveloperActionButton(
                        title: "Reset to Auto",
                        subtitle: "Drop custom path overrides and return to auto-detection.",
                        action: onResetToAuto
                    )
                }
            }
        }
        .padding(14)
        .tokenmonAdaptiveSurface(
            cornerRadius: 16,
            strokeColor: Color.secondary.opacity(0.10)
        )
    }
}

private struct TokenmonDeveloperAppLogRow: View {
    let entry: TokenmonAppLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.timestamp)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Text(entry.level.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelTint)

                Text(entry.category)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(entry.event)
                .font(.caption.weight(.medium))

            if entry.metadata.isEmpty == false {
                Text(
                    entry.metadata
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: "  ")
                )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var levelTint: Color {
        switch entry.level {
        case .debug:
            return .secondary
        case .info:
            return .blue
        case .notice:
            return .green
        case .error:
            return .red
        }
    }
}

private struct TokenmonDeveloperDomainEventRow: View {
    let record: PersistedDomainEventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.eventType)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(record.occurredAt)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(record.aggregateType ?? "aggregate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let aggregateID = record.aggregateID {
                    Text(aggregateID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(payloadPreview)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .tokenmonAdaptiveSurface(cornerRadius: 12)
    }

    private var payloadPreview: String {
        let payload = record.payloadJSON
        if payload.count <= 180 {
            return payload
        }
        return String(payload.prefix(180)) + "..."
    }
}

private struct TokenmonDeveloperProviderSessionRow: View {
    let session: ProviderSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(session.provider.displayName) · \(session.providerSessionID)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(session.sessionState.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Mode: \(session.sourceMode) • Last Seen: \(session.lastSeenAt)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let modelSlug = session.modelSlug {
                Text("Model: \(modelSlug)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let workspaceDir = session.workspaceDir {
                Text(workspaceDir)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let transcriptPath = session.transcriptPath {
                Text(transcriptPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .tokenmonAdaptiveSurface(cornerRadius: 12)
    }
}

private struct TokenmonDeveloperIngestEventRow: View {
    let event: ProviderIngestEventSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(event.provider.displayName) · \(event.sourceMode)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(event.acceptanceState.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.acceptanceState == "accepted" ? .green : .orange)
            }

            Text("Observed: \(event.observedAt)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let providerSessionID = event.providerSessionID {
                Text("Session: \(providerSessionID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let rejectionReason = event.rejectionReason {
                Text("Reject: \(rejectionReason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let gameplayEligibility = event.gameplayEligibility {
                Text(
                    "Gameplay: \(gameplayEligibility) · Delta \(event.gameplayDeltaTokens ?? 0)"
                )
                .font(.caption2)
                .foregroundStyle(gameplayEligibility == UsageSampleGameplayEligibility.eligibleLive.rawValue ? .green : .secondary)
            }

            Text(event.providerEventFingerprint)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .tokenmonAdaptiveSurface(cornerRadius: 12)
    }
}

private struct TokenmonDeveloperBackfillRunRow: View {
    let run: BackfillRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(run.provider.displayName) · \(run.mode)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(run.status.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(run.status == "completed" ? .green : run.status == "failed" ? .orange : .secondary)
            }

            Text("Started: \(run.startedAt)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let completedAt = run.completedAt {
                Text("Completed: \(completedAt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Examined \(run.samplesExamined) • Created \(run.samplesCreated) • Duplicates \(run.duplicatesSkipped) • Errors \(run.errorsCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let summaryJSON = run.summaryJSON {
                Text(summaryJSON)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .tokenmonAdaptiveSurface(cornerRadius: 12)
    }
}

private struct TokenmonDeveloperDiagnosticCard: View {
    let summary: ProviderHealthSummary
    let nextStep: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.provider.displayName)
                    .font(.headline)
                Spacer()
                TokenmonDeveloperStateBadge(healthState: summary.healthState)
            }

            Text(summary.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            TokenmonDeveloperInfoRow(title: "Support", value: summary.supportLevel, systemImage: "shield", tint: .secondary)
            TokenmonDeveloperInfoRow(title: "Mode", value: summary.sourceMode ?? "unknown", systemImage: "antenna.radiowaves.left.and.right", tint: .secondary)
            TokenmonDeveloperInfoRow(title: "Offline Recovery", value: summary.offlineDashboardRecovery, systemImage: "arrow.clockwise.circle", tint: .secondary)
            TokenmonDeveloperInfoRow(title: "Gameplay Armed", value: summary.liveGameplayArmed ? "yes" : "no", systemImage: "gamecontroller", tint: summary.liveGameplayArmed ? .green : .secondary)
            TokenmonDeveloperInfoRow(title: "Observed", value: summary.lastObservedAt ?? "none", systemImage: "clock", tint: .secondary)
            TokenmonDeveloperInfoRow(title: "Next", value: nextStep, systemImage: "arrow.turn.down.right", tint: .secondary)

            if let lastError = summary.lastErrorSummary {
                TokenmonDeveloperInfoRow(title: "Last Error", value: lastError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }

            if let lastBackfill = summary.lastBackfillSummary {
                TokenmonDeveloperInfoRow(title: "Last Backfill", value: lastBackfill, systemImage: "arrow.clockwise.circle", tint: .secondary)
            }
        }
        .padding(14)
        .tokenmonAdaptiveSurface(
            cornerRadius: 16,
            strokeColor: Color.secondary.opacity(0.10)
        )
    }
}

private struct TokenmonDeveloperInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct TokenmonDeveloperStateBadge: View {
    let title: String
    let tint: Color
    let systemImage: String

    init(state: TokenmonProviderCardState) {
        switch state {
        case .connected:
            title = "Connected"
            tint = .green
            systemImage = "checkmark.circle.fill"
        case .repair:
            title = "Repair"
            tint = .orange
            systemImage = "wrench.and.screwdriver.fill"
        case .needsSetup:
            title = "Needs Setup"
            tint = .accentColor
            systemImage = "exclamationmark.circle.fill"
        case .notFound:
            title = "Not Found"
            tint = .secondary
            systemImage = "magnifyingglass"
        }
    }

    init(healthState: String) {
        switch healthState {
        case "active", "connected":
            title = "Active"
            tint = .green
            systemImage = "checkmark.circle.fill"
        case "experimental":
            title = "Experimental"
            tint = .orange
            systemImage = "flask.fill"
        case "degraded", "unsupported":
            title = "Needs Attention"
            tint = .red
            systemImage = "exclamationmark.triangle.fill"
        default:
            title = healthState.replacingOccurrences(of: "_", with: " ").capitalized
            tint = .secondary
            systemImage = "info.circle.fill"
        }
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}
