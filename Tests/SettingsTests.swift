import AppKit
import SwiftUI
import Testing
@testable import Pad

@MainActor
@Suite struct SettingsTests {
    @Test func freshSettingsUsePadDefaults() {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.showInDock)
        #expect(settings.menuBarItem)
        #expect(settings.menuBarIcon == .mark)
        #expect(settings.accent == .standard)
        #expect(settings.customAccent == "BEBAFC")
    }

    @Test func appearancePreferencesPersistIndependently() {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let otherSuite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let other = UserDefaults(suiteName: otherSuite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            other.removePersistentDomain(forName: otherSuite)
        }
        let settings = AppSettings(defaults: defaults)
        settings.menuBarItem = false
        settings.menuBarIcon = .compose
        settings.accent = .custom
        settings.setCustomAccent(Color(red: 0.2, green: 0.4, blue: 0.6))
        let restored = AppSettings(defaults: defaults)
        #expect(!restored.menuBarItem)
        #expect(restored.menuBarIcon == .compose)
        #expect(restored.accent == .custom)
        #expect(restored.customAccent == "336699")
        let isolated = AppSettings(defaults: other)
        #expect(isolated.menuBarItem)
        #expect(isolated.accent == .standard)
    }

    @Test(arguments: [AppAccess.dock, .menuBar, .both, .shortcutOnly])
    func accessPreservesExistingVisibilityPreferences(_ access: AppAccess) {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(access.showInDock, forKey: "showInDock")
        defaults.set(access.menuBarItem, forKey: "menuBarItem")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.access == access)
        #expect(defaults.bool(forKey: "showInDock") == access.showInDock)
        #expect(defaults.bool(forKey: "menuBarItem") == access.menuBarItem)
        #expect(!AppAccess.visibleChoices.contains(.shortcutOnly))
    }

    @Test func accessCannotRemoveBothEntryPointsWithoutShortcut() {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        settings.setAccess(.shortcutOnly, hasGlobalShortcut: false)

        #expect(settings.access == .both)
        #expect(defaults.object(forKey: "showInDock") == nil)
        #expect(defaults.object(forKey: "menuBarItem") == nil)
    }

    @Test func ordinaryLaunchesAreNotLoginLaunches() {
        #expect(!LoginItemSettings.isLoginLaunch(nil))
        let event = launchEvent()
        #expect(!LoginItemSettings.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(enumCode: 0), forKeyword: keyAEPropData)
        #expect(!LoginItemSettings.isLoginLaunch(event))
    }

    @Test(arguments: [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem])
    func loginAndServiceLaunchEventsAreRecognized(_ launchCode: OSType) {
        let event = launchEvent()
        event.setParam(NSAppleEventDescriptor(enumCode: launchCode), forKeyword: keyAEPropData)
        #expect(LoginItemSettings.isLoginLaunch(event))
    }

    @Test func launchMetadataOnOtherEventsDoesNotSuppressAnOrdinaryReopen() {
        let event = launchEvent(id: kAEReopenApplication)
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        #expect(!LoginItemSettings.isLoginLaunch(event))
    }

    private func launchEvent(id: AEEventID = kAEOpenApplication) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: id, targetDescriptor: nil,
                               returnID: AEReturnID(kAutoGenerateReturnID),
                               transactionID: AETransactionID(kAnyTransactionID))
    }

    @Test func systemAccentUsesMacOSColor() {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.accent = .system
        #expect(settings.accentColor == Color(nsColor: .controlAccentColor))
    }
}
