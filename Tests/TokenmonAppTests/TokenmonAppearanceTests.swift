import AppKit
import SwiftUI
import Testing
@testable import TokenmonApp
@testable import TokenmonPersistence

struct TokenmonAppearanceTests {
    @Test
    func adaptiveChromeResolutionPrefersCompatibilityWhenForcedOrRequired() {
        #expect(
            TokenmonAdaptiveChromeController.shouldUseCompatibilityChrome(
                forceCompatibilityChrome: false,
                runtimeSupportsNativeGlass: true
            ) == false
        )
        #expect(
            TokenmonAdaptiveChromeController.shouldUseCompatibilityChrome(
                forceCompatibilityChrome: true,
                runtimeSupportsNativeGlass: true
            ) == true
        )
        #expect(
            TokenmonAdaptiveChromeController.shouldUseCompatibilityChrome(
                forceCompatibilityChrome: false,
                runtimeSupportsNativeGlass: false
            ) == true
        )
    }

    @Test
    func appAppearancePreferenceMapsToNativeAppearanceOverrides() {
        #expect(AppAppearancePreference.system.appKitAppearanceName == nil)
        #expect(AppAppearancePreference.light.appKitAppearanceName == .aqua)
        #expect(AppAppearancePreference.dark.appKitAppearanceName == .darkAqua)
        #expect(AppAppearancePreference.system.colorSchemeOverride == nil)
        #expect(AppAppearancePreference.light.colorSchemeOverride == .light)
        #expect(AppAppearancePreference.dark.colorSchemeOverride == .dark)
    }

    @Test
    @MainActor
    func appAppearanceControllerResetsExistingHostWindowsWhenReturningToSystem() {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        defer {
            window.orderOut(nil)
            TokenmonAppAppearanceController.syncHostWindow(window, appearance: originalAppearance)
            application.appearance = originalAppearance
        }

        TokenmonAppAppearanceController.apply(.dark, application: application)
        TokenmonAppAppearanceController.syncHostWindow(window, appearance: application.appearance)
        #expect(application.appearance?.name == .darkAqua)
        #expect(window.appearance?.name == .darkAqua)

        TokenmonAppAppearanceController.apply(.system, application: application)
        TokenmonAppAppearanceController.syncHostWindow(window, appearance: application.appearance)
        #expect(application.appearance == nil)
        #expect(window.appearance == nil)
    }
}
