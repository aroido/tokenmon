import AppKit
import Foundation
import TokenmonPersistence
@preconcurrency import UserNotifications

enum TokenmonNotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized(alertsEnabled: Bool, soundsEnabled: Bool, alertStyle: Int)
}

@MainActor
protocol TokenmonCaptureNotificationCoordinating: AnyObject {
    func start()
    func fetchAuthorizationState(
        completion: @escaping @MainActor (TokenmonNotificationAuthorizationState) -> Void
    )
    func runtimeDidRefresh(
        from previous: TokenmonRuntimeSnapshot,
        to current: TokenmonRuntimeSnapshot,
        settings: AppSettings
    )
    func sendPreviewCaptureNotification(
        speciesID: String,
        assetKey: String,
        speciesName: String,
        subtitle: String,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    )
    func notificationsPreferenceDidChange(
        isEnabled: Bool,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    )
    func updateNotificationsPreferenceDidChange(
        isEnabled: Bool,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    )
    func sendUpdateAvailableNotification(
        version: String,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    )
}

@MainActor
final class TokenmonNoopCaptureNotificationCoordinator: TokenmonCaptureNotificationCoordinating {
    func start() {}

    func fetchAuthorizationState(
        completion: @escaping @MainActor (TokenmonNotificationAuthorizationState) -> Void
    ) {
        completion(.unknown)
    }

    func runtimeDidRefresh(
        from _: TokenmonRuntimeSnapshot,
        to _: TokenmonRuntimeSnapshot,
        settings _: AppSettings
    ) {}

    func sendPreviewCaptureNotification(
        speciesID _: String,
        assetKey _: String,
        speciesName _: String,
        subtitle _: String,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    ) {
        completion(nil, nil)
    }

    func notificationsPreferenceDidChange(
        isEnabled _: Bool,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    ) {
        completion(nil, nil)
    }

    func updateNotificationsPreferenceDidChange(
        isEnabled _: Bool,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    ) {
        completion(nil, nil)
    }

    func sendUpdateAvailableNotification(
        version _: String,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        completion?(false)
    }
}

@MainActor
final class TokenmonCaptureNotificationCoordinator: NSObject, TokenmonCaptureNotificationCoordinating {
    private enum Constants {
        static let speciesIDUserInfoKey = "species_id"
        static let encounterIDUserInfoKey = "encounter_id"
        static let updateVersionUserInfoKey = "update_version"
        static let requestIdentifierPrefix = "tokenmon.capture."
        static let updateRequestIdentifierPrefix = "tokenmon.update."
        static let attachmentIdentifier = "captured-species"
        static let previewDelaySeconds: TimeInterval = 2
        static let previewDeliveryCheckDelaySeconds: TimeInterval = 5
    }

    private let notificationCenter: UNUserNotificationCenter
    private let supportDirectoryPath: String
    private var authorizationRequestInFlight = false
    var onOpenCapturedSpecies: ((String) -> Void)?
    var onCaptureNotificationOpened: ((String, String) -> Void)?
    var onOpenAvailableUpdate: ((String) -> Void)?

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        supportDirectoryPath: String = TokenmonDatabaseManager.supportDirectory()
    ) {
        self.notificationCenter = notificationCenter
        self.supportDirectoryPath = supportDirectoryPath
        super.init()
    }

    func start() {
        logNotice(event: "notification_coordinator_started")
        notificationCenter.delegate = self
    }

    func fetchAuthorizationState(
        completion: @escaping @MainActor (TokenmonNotificationAuthorizationState) -> Void
    ) {
        notificationCenter.getNotificationSettings { settings in
            let authorizationStatus = settings.authorizationStatus
            let alertsEnabled = settings.alertSetting == .enabled
            let soundsEnabled = settings.soundSetting == .enabled
            let alertStyle = settings.alertStyle.rawValue

            Task { @MainActor in
                self.logDebug(
                    event: "notification_authorization_state_fetched",
                    metadata: [
                        "authorization_status": "\(authorizationStatus.rawValue)",
                        "alerts_enabled": String(alertsEnabled),
                        "sounds_enabled": String(soundsEnabled),
                        "alert_style": "\(alertStyle)",
                    ]
                )
                completion(
                    Self.authorizationState(
                        authorizationStatus: authorizationStatus,
                        alertsEnabled: alertsEnabled,
                        soundsEnabled: soundsEnabled,
                        alertStyle: alertStyle
                    )
                )
            }
        }
    }

    func runtimeDidRefresh(
        from previous: TokenmonRuntimeSnapshot,
        to current: TokenmonRuntimeSnapshot,
        settings: AppSettings
    ) {
        guard settings.notificationsEnabled else {
            return
        }

        let captures = Self.captureCandidates(previous: previous, current: current)
        guard captures.isEmpty == false else {
            return
        }

        ensureAuthorization(promptIfNeeded: false) { [weak self] authorized in
            guard let self, authorized else {
                return
            }
            Task { [weak self] in
                guard let self else {
                    return
                }
                await MainActor.run {
                    for encounter in captures {
                        self.scheduleCaptureNotification(for: encounter)
                    }
                }
            }
        }
    }

    func notificationsPreferenceDidChange(
        isEnabled: Bool,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    ) {
        guard isEnabled else {
            completion(nil, nil)
            return
        }

        ensureAuthorization(promptIfNeeded: true) { authorized in
            Task { @MainActor in
                if authorized {
                    completion(
                        TokenmonL10n.string("settings.feedback.capture_notifications_enabled"),
                        nil
                    )
                } else {
                    completion(
                        nil,
                        TokenmonL10n.string("settings.feedback.capture_notifications_denied")
                    )
                }
            }
        }
    }

    func updateNotificationsPreferenceDidChange(
        isEnabled: Bool,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    ) {
        guard isEnabled else {
            completion(nil, nil)
            return
        }

        ensureAuthorization(promptIfNeeded: true) { authorized in
            Task { @MainActor in
                if authorized {
                    completion(
                        TokenmonL10n.string("settings.feedback.update_notifications_enabled"),
                        nil
                    )
                } else {
                    completion(
                        nil,
                        TokenmonL10n.string("settings.feedback.update_notifications_denied")
                    )
                }
            }
        }
    }

    func sendPreviewCaptureNotification(
        speciesID: String,
        assetKey: String,
        speciesName: String,
        subtitle: String,
        completion: @escaping @MainActor (_ message: String?, _ error: String?) -> Void
    ) {
        ensureAuthorization(promptIfNeeded: false) { [weak self] authorized in
            guard let self else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard authorized else {
                    self.logError(
                        event: "preview_capture_alert_blocked",
                        metadata: ["species_id": speciesID]
                    )
                    completion(
                        nil,
                        TokenmonL10n.string("settings.feedback.preview_alert_notifications_unavailable")
                    )
                    return
                }

                self.scheduleCaptureNotification(
                    speciesID: speciesID,
                    assetKey: assetKey,
                    encounterID: "preview.\(UUID().uuidString.lowercased())",
                    speciesName: speciesName,
                    subtitle: subtitle,
                    body: "Open Dex to view this species entry.",
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: Constants.previewDelaySeconds,
                        repeats: false
                    )
                ) { error in
                    if let error {
                        self.logError(
                            event: "preview_capture_alert_failed",
                            metadata: [
                                "species_id": speciesID,
                                "error": error.localizedDescription,
                            ]
                        )
                        completion(nil, error.localizedDescription)
                    } else {
                        self.logNotice(
                            event: "preview_capture_alert_scheduled",
                            metadata: ["species_id": speciesID]
                        )
                        self.prepareForBackgroundPreview()
                        completion(
                            TokenmonL10n.string("settings.feedback.preview_alert_scheduled"),
                            nil
                        )
                    }
                }
            }
        }
    }

    func sendUpdateAvailableNotification(
        version: String,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedVersion.isEmpty == false else {
            Self.notifyUpdateCompletion(completion, scheduled: false)
            return
        }

        ensureAuthorization(promptIfNeeded: false) { [weak self] authorized in
            guard let self else {
                Self.notifyUpdateCompletion(completion, scheduled: false)
                return
            }

            guard authorized else {
                Self.logStaticDebug(
                    supportDirectoryPath: self.supportDirectoryPath,
                    event: "update_alert_blocked",
                    metadata: ["version": trimmedVersion]
                )
                Self.notifyUpdateCompletion(completion, scheduled: false)
                return
            }

            let supportDirectoryPath = self.supportDirectoryPath
            let notificationCenter = self.notificationCenter
            let request = Self.updateNotificationRequest(version: trimmedVersion)
            notificationCenter.add(request) { error in
                if let error {
                    Self.logStaticError(
                        supportDirectoryPath: supportDirectoryPath,
                        event: "update_alert_schedule_failed",
                        metadata: [
                            "version": trimmedVersion,
                            "error": error.localizedDescription,
                        ]
                    )
                    Self.notifyUpdateCompletion(completion, scheduled: false)
                    return
                }

                Self.logStaticNotice(
                    supportDirectoryPath: supportDirectoryPath,
                    event: "update_alert_scheduled",
                    metadata: ["version": trimmedVersion]
                )
                Self.notifyUpdateCompletion(completion, scheduled: true)
            }
        }
    }

    static func captureCandidates(
        previous: TokenmonRuntimeSnapshot,
        current: TokenmonRuntimeSnapshot
    ) -> [RecentEncounterSummary] {
        TokenmonEncounterDeltaResolver.newEncounters(previous: previous, current: current)
            .filter { $0.outcome == .captured }
    }

    private static func authorizationState(
        authorizationStatus: UNAuthorizationStatus,
        alertsEnabled: Bool,
        soundsEnabled: Bool,
        alertStyle: Int
    ) -> TokenmonNotificationAuthorizationState {
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        default:
            return .authorized(alertsEnabled: alertsEnabled, soundsEnabled: soundsEnabled, alertStyle: alertStyle)
        }
    }

    private func scheduleCaptureNotification(for encounter: RecentEncounterSummary) {
        scheduleCaptureNotification(
            speciesID: encounter.speciesID,
            assetKey: encounter.assetKey,
            encounterID: encounter.encounterID,
            speciesName: encounter.speciesName,
            subtitle: TokenmonL10n.format("capture.notification.subtitle", encounter.rarity.displayName, encounter.field.displayName),
            body: TokenmonL10n.string("capture.notification.body"),
            trigger: nil,
            completion: nil
        )
    }

    private func scheduleCaptureNotification(
        speciesID: String,
        assetKey: String,
        encounterID: String,
        speciesName: String,
        subtitle: String,
        body: String,
        trigger: UNNotificationTrigger?,
        completion: (@MainActor @Sendable (Error?) -> Void)?
    ) {
        let identifier = Constants.requestIdentifierPrefix + encounterID
        let attachment = notificationAttachment(assetKey: assetKey)
        let hasAttachment = attachment != nil
        let request = notificationRequest(
            identifier: identifier,
            speciesID: speciesID,
            encounterID: encounterID,
            speciesName: speciesName,
            subtitle: subtitle,
            body: body,
            attachment: attachment,
            trigger: trigger
        )
        let fallbackRequest = notificationRequest(
            identifier: identifier,
            speciesID: speciesID,
            encounterID: encounterID,
            speciesName: speciesName,
            subtitle: subtitle,
            body: body,
            attachment: nil,
            trigger: trigger
        )

        notificationCenter.add(request) { [notificationCenter] error in
            guard let error, hasAttachment else {
                if let error {
                    Self.logStaticError(
                        supportDirectoryPath: self.supportDirectoryPath,
                        event: "capture_alert_schedule_failed",
                        metadata: [
                            "encounter_id": encounterID,
                            "error": error.localizedDescription,
                        ]
                    )
                } else {
                    Self.logStaticNotice(
                        supportDirectoryPath: self.supportDirectoryPath,
                        event: "capture_alert_scheduled",
                        metadata: [
                            "encounter_id": encounterID,
                            "species_id": speciesID,
                            "has_attachment": String(hasAttachment),
                        ]
                    )
                }
                Self.logPendingAndDelivered(
                    supportDirectoryPath: self.supportDirectoryPath,
                    notificationCenter: notificationCenter,
                    identifier: identifier
                )
                if encounterID.hasPrefix("preview.") {
                    Self.scheduleDeliveryRecheck(
                        supportDirectoryPath: self.supportDirectoryPath,
                        notificationCenter: notificationCenter,
                        identifier: identifier
                    )
                }
                Self.notifyCompletion(completion, error: error)
                return
            }

            Self.logStaticError(
                supportDirectoryPath: self.supportDirectoryPath,
                event: "capture_alert_attachment_failed_retrying_without_attachment",
                metadata: [
                    "encounter_id": encounterID,
                    "species_id": speciesID,
                    "error": error.localizedDescription,
                ]
            )
            notificationCenter.add(fallbackRequest) { fallbackError in
                if let fallbackError {
                    Self.logStaticError(
                        supportDirectoryPath: self.supportDirectoryPath,
                        event: "capture_alert_fallback_schedule_failed",
                        metadata: [
                            "encounter_id": encounterID,
                            "species_id": speciesID,
                            "error": fallbackError.localizedDescription,
                        ]
                    )
                } else {
                    Self.logStaticNotice(
                        supportDirectoryPath: self.supportDirectoryPath,
                        event: "capture_alert_scheduled_without_attachment",
                        metadata: [
                            "encounter_id": encounterID,
                            "species_id": speciesID,
                        ]
                    )
                }
                Self.logPendingAndDelivered(
                    supportDirectoryPath: self.supportDirectoryPath,
                    notificationCenter: notificationCenter,
                    identifier: identifier
                )
                if encounterID.hasPrefix("preview.") {
                    Self.scheduleDeliveryRecheck(
                        supportDirectoryPath: self.supportDirectoryPath,
                        notificationCenter: notificationCenter,
                        identifier: identifier
                    )
                }
                Self.notifyCompletion(completion, error: fallbackError ?? error)
            }
        }
    }

    nonisolated private static func notifyCompletion(
        _ completion: (@MainActor @Sendable (Error?) -> Void)?,
        error: Error?
    ) {
        guard let completion else {
            return
        }
        Task { @MainActor in
            completion(error)
        }
    }

    nonisolated private static func notifyUpdateCompletion(
        _ completion: (@MainActor @Sendable (Bool) -> Void)?,
        scheduled: Bool
    ) {
        guard let completion else {
            return
        }

        Task { @MainActor in
            completion(scheduled)
        }
    }

    private func notificationRequest(
        identifier: String,
        speciesID: String,
        encounterID: String,
        speciesName: String,
        subtitle: String,
        body: String,
        attachment: UNNotificationAttachment?,
        trigger: UNNotificationTrigger?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Captured \(speciesName)"
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.userInfo = [
            Constants.speciesIDUserInfoKey: speciesID,
            Constants.encounterIDUserInfoKey: encounterID,
        ]
        if let attachment {
            content.attachments = [attachment]
        }

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }

    nonisolated private static func updateNotificationRequest(version: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = TokenmonL10n.string("update.notification.title")
        content.subtitle = TokenmonL10n.format("update.notification.subtitle", version)
        content.body = TokenmonL10n.string("update.notification.body")
        content.sound = .default
        content.userInfo = [Constants.updateVersionUserInfoKey: version]

        return UNNotificationRequest(
            identifier: Constants.updateRequestIdentifierPrefix + version,
            content: content,
            trigger: nil
        )
    }

    private func notificationAttachment(assetKey: String) -> UNNotificationAttachment? {
        guard let url = TokenmonSpeciesSpriteLoader.notificationAttachmentURL(assetKey: assetKey) else {
            return nil
        }

        return try? UNNotificationAttachment(
            identifier: Constants.attachmentIdentifier,
            url: url
        )
    }

    private func ensureAuthorization(
        promptIfNeeded: Bool,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            let authorizationStatus = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else {
                    completion(false)
                    return
                }

                switch authorizationStatus {
                case .notDetermined:
                    guard promptIfNeeded, self.authorizationRequestInFlight == false else {
                        self.logDebug(event: "notification_authorization_prompt_skipped")
                        completion(false)
                        return
                    }
                    self.authorizationRequestInFlight = true
                    self.logNotice(event: "notification_authorization_prompt_requested")
                    let notificationCenter = self.notificationCenter
                    Task { [weak self] in
                        let granted = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
                        await MainActor.run {
                            self?.authorizationRequestInFlight = false
                            self?.logNotice(
                                event: "notification_authorization_prompt_completed",
                                metadata: ["granted": String(granted)]
                            )
                            completion(granted)
                        }
                    }
                case .denied:
                    self.logDebug(event: "notification_authorization_denied_state")
                    completion(false)
                default:
                    self.logDebug(event: "notification_authorization_already_available")
                    completion(true)
                }
            }
        }
    }

    private func prepareForBackgroundPreview() {
        logNotice(event: "preview_capture_alert_backgrounding_app")
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.hide(nil)
        }
    }

    private func logDebug(event: String, metadata: [String: String] = [:]) {
        Self.logStaticDebug(supportDirectoryPath: supportDirectoryPath, event: event, metadata: metadata)
    }

    private func logNotice(event: String, metadata: [String: String] = [:]) {
        Self.logStaticNotice(supportDirectoryPath: supportDirectoryPath, event: event, metadata: metadata)
    }

    private func logError(event: String, metadata: [String: String] = [:]) {
        Self.logStaticError(supportDirectoryPath: supportDirectoryPath, event: event, metadata: metadata)
    }

    nonisolated private static func logStaticDebug(
        supportDirectoryPath: String,
        event: String,
        metadata: [String: String] = [:]
    ) {
        TokenmonAppBehaviorLogger.debug(
            category: "notifications",
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    nonisolated private static func logStaticNotice(
        supportDirectoryPath: String,
        event: String,
        metadata: [String: String] = [:]
    ) {
        TokenmonAppBehaviorLogger.notice(
            category: "notifications",
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    nonisolated private static func logStaticError(
        supportDirectoryPath: String,
        event: String,
        metadata: [String: String] = [:]
    ) {
        TokenmonAppBehaviorLogger.error(
            category: "notifications",
            event: event,
            metadata: metadata,
            supportDirectoryPath: supportDirectoryPath
        )
    }

    nonisolated private static func logPendingAndDelivered(
        supportDirectoryPath: String,
        notificationCenter: UNUserNotificationCenter,
        identifier: String
    ) {
        notificationCenter.getPendingNotificationRequests { requests in
            let pending = requests.contains { $0.identifier == identifier }
            logStaticDebug(
                supportDirectoryPath: supportDirectoryPath,
                event: "capture_alert_pending_state_checked",
                metadata: [
                    "identifier": identifier,
                    "pending": String(pending),
                ]
            )
        }

        notificationCenter.getDeliveredNotifications { notifications in
            let delivered = notifications.contains { $0.request.identifier == identifier }
            logStaticDebug(
                supportDirectoryPath: supportDirectoryPath,
                event: "capture_alert_delivered_state_checked",
                metadata: [
                    "identifier": identifier,
                    "delivered": String(delivered),
                ]
            )
        }
    }

    nonisolated private static func scheduleDeliveryRecheck(
        supportDirectoryPath: String,
        notificationCenter: UNUserNotificationCenter,
        identifier: String
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.previewDeliveryCheckDelaySeconds) {
            notificationCenter.getPendingNotificationRequests { requests in
                let pending = requests.contains { $0.identifier == identifier }
                logStaticDebug(
                    supportDirectoryPath: supportDirectoryPath,
                    event: "preview_capture_alert_pending_state_rechecked",
                    metadata: [
                        "identifier": identifier,
                        "pending": String(pending),
                    ]
                )
            }

            notificationCenter.getDeliveredNotifications { notifications in
                let delivered = notifications.contains { $0.request.identifier == identifier }
                logStaticDebug(
                    supportDirectoryPath: supportDirectoryPath,
                    event: "preview_capture_alert_delivered_state_rechecked",
                    metadata: [
                        "identifier": identifier,
                        "delivered": String(delivered),
                    ]
                )
            }
        }
    }
}

extension TokenmonCaptureNotificationCoordinator: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix(Constants.updateRequestIdentifierPrefix) {
            let version = notification.request.content.userInfo[Constants.updateVersionUserInfoKey] as? String ?? "unknown"
            Self.logStaticNotice(
                supportDirectoryPath: supportDirectoryPath,
                event: "update_alert_will_present",
                metadata: ["version": version]
            )
            completionHandler([.list, .banner, .sound])
            return
        }

        let encounterID = notification.request.content.userInfo[Constants.encounterIDUserInfoKey] as? String ?? "unknown"
        Self.logStaticNotice(
            supportDirectoryPath: supportDirectoryPath,
            event: "capture_alert_will_present",
            metadata: ["encounter_id": encounterID]
        )
        completionHandler([.list, .banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.hasPrefix(Constants.updateRequestIdentifierPrefix) {
            let version = response.notification.request.content.userInfo[Constants.updateVersionUserInfoKey] as? String ?? "unknown"
            Self.logStaticNotice(
                supportDirectoryPath: supportDirectoryPath,
                event: "update_alert_response_received",
                metadata: ["version": version]
            )

            Task { @MainActor [weak self] in
                self?.onOpenAvailableUpdate?(version)
            }

            completionHandler()
            return
        }

        let speciesID = response.notification.request.content.userInfo[Constants.speciesIDUserInfoKey] as? String
        let encounterID = response.notification.request.content.userInfo[Constants.encounterIDUserInfoKey] as? String ?? "unknown"

        Self.logStaticNotice(
            supportDirectoryPath: supportDirectoryPath,
            event: "capture_alert_response_received",
            metadata: ["encounter_id": encounterID]
        )

        if let speciesID {
            Task { @MainActor [weak self] in
                self?.onCaptureNotificationOpened?(speciesID, encounterID)
                self?.onOpenCapturedSpecies?(speciesID)
            }
        }

        completionHandler()
    }
}
