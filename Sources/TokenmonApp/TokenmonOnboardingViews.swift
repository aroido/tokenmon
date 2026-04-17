import Foundation
import SwiftUI
import TokenmonDomain
import TokenmonPersistence

enum TokenmonSetupRecommendationAction: Equatable, Sendable {
    case enableLaunchAtLogin
    case openLoginItemsSettings
    case enableCaptureNotifications
    case requestCaptureNotificationPermission
    case openNotificationSettings
}

enum TokenmonSetupRecommendationTint: Equatable, Sendable {
    case secondary
    case green
    case orange
    case red

    @MainActor
    var color: Color {
        switch self {
        case .secondary:
            return .secondary
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        }
    }
}

struct TokenmonSetupRecommendationItem: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
    let tint: TokenmonSetupRecommendationTint
    let actionTitle: String?
    let action: TokenmonSetupRecommendationAction?
}

enum TokenmonSetupRecommendationsBuilder {
    static func items(
        appSettings: AppSettings,
        launchAtLoginState: TokenmonLaunchAtLoginState,
        notificationAuthorizationState: TokenmonNotificationAuthorizationState
    ) -> [TokenmonSetupRecommendationItem] {
        var results: [TokenmonSetupRecommendationItem] = []

        if let launchRecommendation = launchRecommendation(for: launchAtLoginState) {
            results.append(launchRecommendation)
        }

        if let notificationRecommendation = notificationRecommendation(
            appSettings: appSettings,
            authorizationState: notificationAuthorizationState
        ) {
            results.append(notificationRecommendation)
        }

        return results
    }

    static func launchStatusSymbol(_ state: TokenmonLaunchAtLoginState) -> String {
        if state.isSupported == false {
            return "exclamationmark.triangle.fill"
        }

        return state.isEnabled ? "checkmark.circle.fill" : "info.circle.fill"
    }

    static func launchStatusTint(_ state: TokenmonLaunchAtLoginState) -> TokenmonSetupRecommendationTint {
        if state.isSupported == false {
            return .orange
        }

        return state.isEnabled ? .green : .secondary
    }

    static func notificationAuthorizationDetail(_ state: TokenmonNotificationAuthorizationState) -> String {
        switch state {
        case .unknown:
            return TokenmonL10n.string("settings.notifications.status.checking")
        case .notDetermined:
            return TokenmonL10n.string("settings.notifications.status.not_determined")
        case .denied:
            return TokenmonL10n.string("settings.notifications.status.denied")
        case .authorized(let alertsEnabled, let soundsEnabled, let alertStyle):
            if alertsEnabled {
                let styleSummary: String
                switch alertStyle {
                case 0:
                    styleSummary = TokenmonL10n.string("settings.notifications.style.none")
                case 1:
                    styleSummary = TokenmonL10n.string("settings.notifications.style.banners")
                case 2:
                    styleSummary = TokenmonL10n.string("settings.notifications.style.alerts")
                default:
                    styleSummary = TokenmonL10n.string("settings.notifications.style.unknown")
                }
                return soundsEnabled
                    ? TokenmonL10n.format("settings.notifications.status.authorized_with_sound", styleSummary)
                    : TokenmonL10n.format("settings.notifications.status.authorized_without_sound", styleSummary)
            }
            return TokenmonL10n.string("settings.notifications.status.alerts_disabled")
        }
    }

    static func notificationAuthorizationSymbol(_ state: TokenmonNotificationAuthorizationState) -> String {
        switch state {
        case .unknown:
            return "hourglass"
        case .notDetermined:
            return "questionmark.circle.fill"
        case .denied:
            return "bell.slash.fill"
        case .authorized(let alertsEnabled, _, _):
            return alertsEnabled ? "checkmark.circle.fill" : "bell.badge.slash.fill"
        }
    }

    static func notificationAuthorizationTint(_ state: TokenmonNotificationAuthorizationState) -> TokenmonSetupRecommendationTint {
        switch state {
        case .unknown:
            return .secondary
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        case .authorized(let alertsEnabled, _, _):
            return alertsEnabled ? .green : .orange
        }
    }

    private static func launchRecommendation(
        for state: TokenmonLaunchAtLoginState
    ) -> TokenmonSetupRecommendationItem? {
        let action: TokenmonSetupRecommendationAction?
        let actionTitle: String?

        if state.isSupported, state.isEnabled == false, state.showsOpenSystemSettingsAction == false {
            action = .enableLaunchAtLogin
            actionTitle = TokenmonL10n.string("settings.general.quick_setup.action.enable_launch_at_login")
        } else if state.showsOpenSystemSettingsAction {
            action = .openLoginItemsSettings
            actionTitle = TokenmonL10n.string("settings.general.open_login_items_settings")
        } else {
            action = nil
            actionTitle = nil
        }

        guard let action else {
            return nil
        }

        return TokenmonSetupRecommendationItem(
            title: TokenmonL10n.string("settings.general.quick_setup.launch_title"),
            detail: state.reason,
            systemImage: launchStatusSymbol(state),
            tint: launchStatusTint(state),
            actionTitle: actionTitle,
            action: action
        )
    }

    private static func notificationRecommendation(
        appSettings: AppSettings,
        authorizationState: TokenmonNotificationAuthorizationState
    ) -> TokenmonSetupRecommendationItem? {
        let detail: String
        let actionTitle: String?
        let action: TokenmonSetupRecommendationAction?

        if appSettings.notificationsEnabled == false {
            detail = notificationAuthorizationDetail(authorizationState)
            actionTitle = TokenmonL10n.string("settings.general.quick_setup.action.enable_capture_notifications")
            action = .enableCaptureNotifications
        } else {
            switch authorizationState {
            case .unknown:
                detail = notificationAuthorizationDetail(authorizationState)
                actionTitle = nil
                action = nil
            case .notDetermined:
                detail = notificationAuthorizationDetail(authorizationState)
                actionTitle = TokenmonL10n.string("settings.general.quick_setup.action.request_notification_permission")
                action = .requestCaptureNotificationPermission
            case .denied:
                detail = notificationAuthorizationDetail(authorizationState)
                actionTitle = TokenmonL10n.string("settings.general.open_notification_settings")
                action = .openNotificationSettings
            case .authorized(let alertsEnabled, _, _):
                if alertsEnabled {
                    detail = TokenmonL10n.string("settings.general.quick_setup.notifications.preference_off")
                    actionTitle = nil
                    action = nil
                } else {
                    detail = notificationAuthorizationDetail(authorizationState)
                    actionTitle = TokenmonL10n.string("settings.general.open_notification_settings")
                    action = .openNotificationSettings
                }
            }
        }

        guard appSettings.notificationsEnabled == false || action != nil else {
            return nil
        }

        return TokenmonSetupRecommendationItem(
            title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
            detail: detail,
            systemImage: notificationAuthorizationSymbol(authorizationState),
            tint: notificationAuthorizationTint(authorizationState),
            actionTitle: actionTitle,
            action: action
        )
    }
}

struct TokenmonSetupRecommendationList: View {
    let items: [TokenmonSetupRecommendationItem]
    let onPerformAction: (TokenmonSetupRecommendationAction) -> Void

    var body: some View {
        if items.isEmpty {
            Label {
                Text(TokenmonL10n.string("settings.general.quick_setup.complete"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    TokenmonSetupRecommendationRow(item: item, onPerformAction: onPerformAction)
                }
            }
        }
    }
}

private struct TokenmonSetupRecommendationRow: View {
    let item: TokenmonSetupRecommendationItem
    let onPerformAction: (TokenmonSetupRecommendationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.tint.color)
            }

            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let actionTitle = item.actionTitle,
               let action = item.action {
                Button(actionTitle) {
                    onPerformAction(action)
                }
                .tokenmonAdaptiveButtonStyle()
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }
}

enum TokenmonFirstRunOnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case setup

    var title: String {
        switch self {
        case .welcome:
            return TokenmonL10n.string("onboarding.welcome.title")
        case .setup:
            return TokenmonL10n.string("onboarding.setup.title")
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return TokenmonL10n.string("onboarding.welcome.subtitle")
        case .setup:
            return TokenmonL10n.string("onboarding.setup.subtitle")
        }
    }

    var index: Int { rawValue + 1 }

    var previous: TokenmonFirstRunOnboardingStep? {
        guard rawValue > 0 else {
            return nil
        }

        return TokenmonFirstRunOnboardingStep(rawValue: rawValue - 1)
    }

    var next: TokenmonFirstRunOnboardingStep? {
        TokenmonFirstRunOnboardingStep(rawValue: rawValue + 1)
    }
}

struct TokenmonOnboardingPanel: View {
    @ObservedObject var model: TokenmonMenuModel
    @State private var currentStep: TokenmonFirstRunOnboardingStep = .welcome

    let onPerformSetupAction: (TokenmonSetupRecommendationAction) -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            TokenmonOnboardingBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                TokenmonOnboardingHeader(
                    title: currentStep.title,
                    subtitle: currentStep.subtitle
                )

                TokenmonOnboardingProgressView(currentStep: currentStep)

                TokenmonSettingsBanner(
                    banner: TokenmonSettingsPresentationBuilder.banner(
                        message: model.settingsMessage,
                        error: model.settingsError
                    )
                )

                ScrollView {
                    Group {
                        switch currentStep {
                        case .welcome:
                            TokenmonOnboardingWelcomeStep()
                        case .setup:
                            TokenmonOnboardingSetupStep(
                                appSettings: model.appSettings,
                                launchAtLoginState: model.launchAtLoginState,
                                notificationAuthorizationState: model.notificationAuthorizationState,
                                onPerformSetupAction: onPerformSetupAction
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                footer
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 500, alignment: .topLeading)
        .environment(\.locale, TokenmonL10n.activeLocale)
        .onAppear {
            model.surfaceOpened(.onboarding, entrypoint: "window_content", emitAnalytics: false)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch currentStep {
        case .welcome:
            HStack {
                Button(TokenmonL10n.string("onboarding.action.skip")) {
                    onSkip()
                }
                .tokenmonAdaptiveButtonStyle()

                Spacer()

                Button(TokenmonL10n.string("onboarding.action.continue")) {
                    currentStep = .setup
                }
                .tokenmonAdaptiveButtonStyle(.prominent)
            }
        case .setup:
            HStack {
                Button(TokenmonL10n.string("common.back")) {
                    currentStep = .welcome
                }
                .tokenmonAdaptiveButtonStyle()

                Spacer()

                Button(TokenmonL10n.string("onboarding.action.finish")) {
                    onFinish()
                }
                .tokenmonAdaptiveButtonStyle(.prominent)
            }
        }
    }
}

private struct TokenmonOnboardingBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.28, green: 0.67, blue: 0.38).opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 32)
                .offset(x: -180, y: -150)

            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 32)
                .offset(x: 210, y: -120)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct TokenmonOnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TokenmonL10n.string("onboarding.header.kicker"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TokenmonOnboardingProgressView: View {
    let currentStep: TokenmonFirstRunOnboardingStep

    var body: some View {
        let allSteps = TokenmonFirstRunOnboardingStep.allCases

        HStack(spacing: 10) {
            ForEach(allSteps, id: \.self) { step in
                TokenmonOnboardingStepPill(
                    step: step,
                    currentStep: currentStep,
                    title: step == .welcome
                        ? TokenmonL10n.string("onboarding.progress.welcome")
                        : TokenmonL10n.string("onboarding.progress.setup")
                )
            }
        }
    }
}

private struct TokenmonOnboardingStepPill: View {
    let step: TokenmonFirstRunOnboardingStep
    let currentStep: TokenmonFirstRunOnboardingStep
    let title: String

    private var isCurrent: Bool { step == currentStep }
    private var isCompleted: Bool { step.rawValue < currentStep.rawValue }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isCurrent ? "sparkles" : isCompleted ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var foregroundColor: Color {
        if isCurrent {
            return .primary
        }
        if isCompleted {
            return Color.accentColor
        }
        return .secondary
    }

    private var backgroundColor: Color {
        if isCurrent {
            return Color(nsColor: .controlBackgroundColor).opacity(0.92)
        }
        if isCompleted {
            return Color.accentColor.opacity(0.10)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.45)
    }

    private var borderColor: Color {
        if isCurrent {
            return Color.accentColor.opacity(0.28)
        }
        if isCompleted {
            return Color.accentColor.opacity(0.18)
        }
        return Color.secondary.opacity(0.08)
    }
}

private enum TokenmonOnboardingBeat: CaseIterable, Hashable {
    case explore
    case encounter
    case resolve
    case dex

    var systemImage: String {
        switch self {
        case .explore:
            return "figure.walk.motion"
        case .encounter:
            return "sparkles.rectangle.stack"
        case .resolve:
            return "wand.and.stars"
        case .dex:
            return "books.vertical"
        }
    }

    var title: String {
        switch self {
        case .explore:
            return TokenmonL10n.string("onboarding.welcome.beat.explore.title")
        case .encounter:
            return TokenmonL10n.string("onboarding.welcome.beat.encounter.title")
        case .resolve:
            return TokenmonL10n.string("onboarding.welcome.beat.resolve.title")
        case .dex:
            return TokenmonL10n.string("onboarding.welcome.beat.dex.title")
        }
    }

    var detail: String {
        switch self {
        case .explore:
            return TokenmonL10n.string("onboarding.welcome.beat.explore.detail")
        case .encounter:
            return TokenmonL10n.string("onboarding.welcome.beat.encounter.detail")
        case .resolve:
            return TokenmonL10n.string("onboarding.welcome.beat.resolve.detail")
        case .dex:
            return TokenmonL10n.string("onboarding.welcome.beat.dex.detail")
        }
    }
}

private struct TokenmonOnboardingWelcomeStep: View {
    private let sceneContext = TokenmonSceneContext(
        sceneState: .exploring,
        fieldKind: .grassland,
        fieldState: .exploring,
        effectState: .none,
        wildState: .hidden
    )

    private var companionAssetKeys: [String] {
        SpeciesCatalog.all
            .filter { $0.isActive && $0.field == FieldType.grassland }
            .prefix(4)
            .map(\.assetKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TokenmonOnboardingHeroCard(
                sceneContext: sceneContext,
                companionAssetKeys: companionAssetKeys
            )

            TokenmonOnboardingNoteStrip(
                title: TokenmonL10n.string("onboarding.welcome.next_steps.title"),
                systemImage: "switch.2",
                detail: TokenmonL10n.string("onboarding.welcome.next_steps.body")
            )
        }
    }
}

private struct TokenmonOnboardingHeroCard: View {
    let sceneContext: TokenmonSceneContext
    let companionAssetKeys: [String]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.95),
                            Color.accentColor.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                Label(TokenmonL10n.string("onboarding.welcome.hero.title"), systemImage: "sparkles")
                    .font(.headline)

                Text(TokenmonL10n.string("onboarding.welcome.hero.body"))
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TokenmonOnboardingHeroBadge(
                        title: TokenmonL10n.string("onboarding.welcome.hero.badge.passive"),
                        systemImage: "leaf.fill"
                    )
                    TokenmonOnboardingHeroBadge(
                        title: TokenmonL10n.string("onboarding.welcome.hero.badge.auto"),
                        systemImage: "wand.and.stars.inverse"
                    )
                    TokenmonOnboardingHeroBadge(
                        title: TokenmonL10n.string("onboarding.welcome.hero.badge.private"),
                        systemImage: "lock.fill"
                    )
                }

                TokenmonNowFieldHeroCard(
                    sceneContext: sceneContext,
                    companionAssetKeys: companionAssetKeys
                )
                .frame(maxWidth: 292, alignment: .leading)
                .allowsHitTesting(false)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(TokenmonOnboardingBeat.allCases, id: \.self) { beat in
                        TokenmonOnboardingBeatPanel(beat: beat)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct TokenmonOnboardingHeroBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct TokenmonOnboardingBeatPanel: View {
    let beat: TokenmonOnboardingBeat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(beat.title)
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: beat.systemImage)
                    .foregroundStyle(Color.accentColor)
            }

            Text(beat.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
    }
}

private struct TokenmonOnboardingSetupStep: View {
    let appSettings: AppSettings
    let launchAtLoginState: TokenmonLaunchAtLoginState
    let notificationAuthorizationState: TokenmonNotificationAuthorizationState
    let onPerformSetupAction: (TokenmonSetupRecommendationAction) -> Void

    private var recommendationItems: [TokenmonSetupRecommendationItem] {
        TokenmonSetupRecommendationsBuilder.items(
            appSettings: appSettings,
            launchAtLoginState: launchAtLoginState,
            notificationAuthorizationState: notificationAuthorizationState
        )
    }

    private var setupCards: [TokenmonOnboardingSetupCardModel] {
        [
            launchSetupCard,
            notificationSetupCard,
        ]
    }

    private var launchSetupCard: TokenmonOnboardingSetupCardModel {
        if launchAtLoginState.isSupported == false {
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.launch_title"),
                systemImage: "power.circle.fill",
                tint: .secondary,
                status: TokenmonL10n.string("onboarding.setup.status.unavailable"),
                detail: launchAtLoginState.reason,
                actionTitle: nil,
                action: nil
            )
        }

        if launchAtLoginState.isEnabled {
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.launch_title"),
                systemImage: "power.circle.fill",
                tint: .green,
                status: TokenmonL10n.string("onboarding.setup.status.ready"),
                detail: launchAtLoginState.reason,
                actionTitle: launchAtLoginState.showsOpenSystemSettingsAction
                    ? TokenmonL10n.string("settings.general.open_login_items_settings")
                    : nil,
                action: launchAtLoginState.showsOpenSystemSettingsAction ? .openLoginItemsSettings : nil
            )
        }

        if launchAtLoginState.showsOpenSystemSettingsAction {
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.launch_title"),
                systemImage: "power.circle.fill",
                tint: .orange,
                status: TokenmonL10n.string("onboarding.setup.status.attention"),
                detail: launchAtLoginState.reason,
                actionTitle: TokenmonL10n.string("settings.general.open_login_items_settings"),
                action: .openLoginItemsSettings
            )
        }

        return TokenmonOnboardingSetupCardModel(
            title: TokenmonL10n.string("settings.general.quick_setup.launch_title"),
            systemImage: "power.circle.fill",
            tint: .accentColor,
            status: TokenmonL10n.string("onboarding.setup.status.optional"),
            detail: launchAtLoginState.reason,
            actionTitle: TokenmonL10n.string("settings.general.quick_setup.action.enable_launch_at_login"),
            action: .enableLaunchAtLogin
        )
    }

    private var notificationSetupCard: TokenmonOnboardingSetupCardModel {
        if appSettings.notificationsEnabled == false {
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
                systemImage: "bell.badge.fill",
                tint: .accentColor,
                status: TokenmonL10n.string("onboarding.setup.status.optional"),
                detail: TokenmonL10n.string("onboarding.setup.notifications.optional"),
                actionTitle: TokenmonL10n.string("settings.general.quick_setup.action.enable_capture_notifications"),
                action: .enableCaptureNotifications
            )
        }

        switch notificationAuthorizationState {
        case .authorized(let alertsEnabled, _, _):
            if alertsEnabled {
                return TokenmonOnboardingSetupCardModel(
                    title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
                    systemImage: "bell.badge.fill",
                    tint: .green,
                    status: TokenmonL10n.string("onboarding.setup.status.ready"),
                    detail: TokenmonL10n.string("onboarding.setup.notifications.ready"),
                    actionTitle: nil,
                    action: nil
                )
            }

            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
                systemImage: "bell.badge.fill",
                tint: .orange,
                status: TokenmonL10n.string("onboarding.setup.status.attention"),
                detail: TokenmonSetupRecommendationsBuilder.notificationAuthorizationDetail(notificationAuthorizationState),
                actionTitle: TokenmonL10n.string("settings.general.open_notification_settings"),
                action: .openNotificationSettings
            )
        case .denied:
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
                systemImage: "bell.badge.fill",
                tint: .orange,
                status: TokenmonL10n.string("onboarding.setup.status.attention"),
                detail: TokenmonSetupRecommendationsBuilder.notificationAuthorizationDetail(notificationAuthorizationState),
                actionTitle: TokenmonL10n.string("settings.general.open_notification_settings"),
                action: .openNotificationSettings
            )
        case .notDetermined:
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
                systemImage: "bell.badge.fill",
                tint: .accentColor,
                status: TokenmonL10n.string("onboarding.setup.status.optional"),
                detail: TokenmonSetupRecommendationsBuilder.notificationAuthorizationDetail(notificationAuthorizationState),
                actionTitle: TokenmonL10n.string("settings.general.quick_setup.action.request_notification_permission"),
                action: .requestCaptureNotificationPermission
            )
        case .unknown:
            return TokenmonOnboardingSetupCardModel(
                title: TokenmonL10n.string("settings.general.quick_setup.notifications_title"),
                systemImage: "bell.badge.fill",
                tint: .secondary,
                status: TokenmonL10n.string("onboarding.setup.status.checking"),
                detail: TokenmonSetupRecommendationsBuilder.notificationAuthorizationDetail(notificationAuthorizationState),
                actionTitle: nil,
                action: nil
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label(TokenmonL10n.string("onboarding.setup.section_title"), systemImage: "switch.2")
                    .font(.headline)

                Text(TokenmonL10n.string("onboarding.setup.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(setupCards) { card in
                        TokenmonOnboardingSetupFeatureCard(
                            card: card,
                            onPerformAction: onPerformSetupAction
                        )
                    }
                }

                if recommendationItems.isEmpty == false {
                    Text(TokenmonL10n.string("settings.general.quick_setup.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(TokenmonL10n.string("settings.general.quick_setup.complete"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TokenmonOnboardingNoteStrip(
                title: TokenmonL10n.string("onboarding.setup.revisit.title"),
                systemImage: "gearshape",
                detail: TokenmonL10n.string("onboarding.setup.revisit.body")
            )
        }
    }
}

private struct TokenmonOnboardingSetupCardModel: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let status: String
    let detail: String
    let actionTitle: String?
    let action: TokenmonSetupRecommendationAction?
}

private struct TokenmonOnboardingSetupFeatureCard: View {
    let card: TokenmonOnboardingSetupCardModel
    let onPerformAction: (TokenmonSetupRecommendationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: card.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(card.tint)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(card.tint.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))

                    Text(card.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(card.tint.opacity(0.12))
                        )
                }

                Spacer(minLength: 0)
            }

            Text(card.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let actionTitle = card.actionTitle,
               let action = card.action {
                Button(actionTitle) {
                    onPerformAction(action)
                }
                .tokenmonAdaptiveButtonStyle(.prominent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(card.tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct TokenmonOnboardingNoteStrip: View {
    let title: String
    let systemImage: String
    let detail: String

    var bodyView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.44))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.06), lineWidth: 1)
        )
    }

    var body: some View {
        bodyView
    }
}

enum TokenmonInstalledAppBundleSupport {
    static func isInstalledAppBundle(
        bundle: Bundle = .main,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let bundleURL = bundle.bundleURL.standardizedFileURL
        let bundlePath = bundleURL.path
        let globalApplications = URL(fileURLWithPath: "/Applications", isDirectory: true).path + "/"
        let userApplications = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path + "/"

        return bundleURL.pathExtension.lowercased() == "app"
            && bundle.bundleIdentifier != nil
            && (bundlePath.hasPrefix(globalApplications) || bundlePath.hasPrefix(userApplications))
    }
}
