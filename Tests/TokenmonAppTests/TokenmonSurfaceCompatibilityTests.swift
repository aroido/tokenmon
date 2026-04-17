import AppKit
import SwiftUI
import Testing
@testable import TokenmonApp
@testable import TokenmonPersistence

@Suite
struct TokenmonSurfaceCompatibilityTests {
    @Test
    @MainActor
    func keySurfacesHostAndRenderWithAdaptiveChrome() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationCoordinator: TokenmonNoopCaptureNotificationCoordinator()
        )

        await model.waitForRefreshToFinish()

        let settingsPanel = TokenmonSettingsPanel(
            model: model,
            appUpdater: TokenmonAppUpdater(),
            onOpenWelcomeGuide: {}
        )
        let onboardingPanel = TokenmonOnboardingPanel(
            model: model,
            onPerformSetupAction: { _ in },
            onSkip: {},
            onFinish: {}
        )
        let developerPanel = TokenmonDeveloperPanel(model: model)
        let popoverContainer = TokenmonPopoverContainer(
            model: model,
            actions: TokenmonPopoverContainerActions(
                openFullDex: {},
                openSettings: { _ in },
                openDeveloperTools: {},
                quit: {},
                selectSpecies: { _ in }
            )
        )

        assertHostedRender(settingsPanel, size: CGSize(width: 760, height: 560))
        assertHostedRender(onboardingPanel, size: CGSize(width: 620, height: 500))
        assertHostedRender(developerPanel, size: CGSize(width: 1040, height: 760))
        assertHostedRender(popoverContainer, size: CGSize(width: 360, height: 480))
    }

    @MainActor
    private func assertHostedRender<Content: View>(_ view: Content, size: CGSize) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let bounds = hostingView.bounds
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            Issue.record("Failed to create a bitmap renderer for \(Content.self)")
            return
        }

        hostingView.cacheDisplay(in: bounds, to: bitmap)

        #expect(bitmap.pixelsWide > 0)
        #expect(bitmap.pixelsHigh > 0)

        window.orderOut(nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-surface-compat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
