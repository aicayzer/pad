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
        #expect(settings.showFormatToggle)
        #expect(settings.showInDock)
        #expect(settings.menuBarItem)
        #expect(settings.menuBarIcon == .mark)
        #expect(settings.accent == .standard)
        #expect(settings.customAccent == "BEBAFC")
    }

    @Test func formatSwitchVisibilityPersistsIndependently() {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("txt", forKey: "pad.format")
        let settings = AppSettings(defaults: defaults)
        settings.showFormatToggle = false
        #expect(!AppSettings(defaults: defaults).showFormatToggle)
        #expect(defaults.string(forKey: "pad.format") == "txt")
        settings.showFormatToggle = true
        #expect(AppSettings(defaults: defaults).showFormatToggle)
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

    @Test func systemAccentUsesMacOSColor() {
        let suite = "pad-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.accent = .system
        #expect(settings.accentColor == Color(nsColor: .controlAccentColor))
    }
}
