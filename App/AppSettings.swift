import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock"); applyActivationPolicy() } }
    var menuBarItem: Bool { didSet { defaults.set(menuBarItem, forKey: "menuBarItem") } }
    var menuBarIcon: MenuBarIcon { didSet { defaults.set(menuBarIcon.rawValue, forKey: "menuBarIcon") } }
    var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    var customAccent: String { didSet { defaults.set(customAccent, forKey: "customAccent") } }
    private(set) var activationPolicyError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInDock = defaults.object(forKey: "showInDock") == nil ? true : defaults.bool(forKey: "showInDock")
        menuBarItem = defaults.object(forKey: "menuBarItem") == nil ? true : defaults.bool(forKey: "menuBarItem")
        menuBarIcon = MenuBarIcon(rawValue: defaults.string(forKey: "menuBarIcon") ?? "") ?? .mark
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        accent = AccentChoice(rawValue: defaults.string(forKey: "accent") ?? "") ?? .standard
        customAccent = defaults.string(forKey: "customAccent") ?? "BEBAFC"
    }

    var access: AppAccess { AppAccess(showInDock: showInDock, menuBarItem: menuBarItem) }

    func setAccess(_ access: AppAccess, hasGlobalShortcut: Bool) {
        guard access != .shortcutOnly || hasGlobalShortcut else { return }
        // Establish the menu entry point before hiding the Dock icon.
        if access.menuBarItem { menuBarItem = true }
        if showInDock != access.showInDock { showInDock = access.showInDock }
        if !access.menuBarItem { menuBarItem = false }
    }

    var accentColor: Color {
        if accent == .system { return Color(nsColor: .controlAccentColor) }
        let value = UInt32(accent == .standard ? "BEBAFC" : customAccent, radix: 16) ?? 0xBEBAFC
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    func setCustomAccent(_ color: Color) {
        guard let color = NSColor(color).usingColorSpace(.sRGB) else { return }
        customAccent = String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nativeAppearance
    }

    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { activationPolicyError = nil; return }
        let wasActive = NSApp.isActive
        let applied = NSApp.setActivationPolicy(policy)
        // Changing policy schedules an activation yield; cancel it while Settings still has focus.
        if applied && wasActive { NSApp.activate() }
        activationPolicyError = applied || NSApp.activationPolicy() == policy
            ? nil : "Could not update Dock visibility. Try changing the setting again."
    }
}

enum AppAccess: String, Identifiable {
    case dock, menuBar, both, shortcutOnly

    static let visibleChoices: [AppAccess] = [.dock, .menuBar, .both]
    var id: String { rawValue }
    var showInDock: Bool { self == .dock || self == .both }
    var menuBarItem: Bool { self == .menuBar || self == .both }
    var title: String {
        switch self {
        case .dock: "Dock"
        case .menuBar: "Menu bar"
        case .both: "Dock and menu bar"
        case .shortcutOnly: "Shortcut only"
        }
    }

    init(showInDock: Bool, menuBarItem: Bool) {
        switch (showInDock, menuBarItem) {
        case (true, true): self = .both
        case (true, false): self = .dock
        case (false, true): self = .menuBar
        case (false, false): self = .shortcutOnly
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case standard, system, custom
    var id: String { rawValue }
    var title: String { switch self { case .standard: "Default"; case .system: "System"; case .custom: "Custom" } }
}

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case mark, text, compose
    var id: String { rawValue }
    var title: String { switch self { case .mark: "App icon"; case .text: "Text"; case .compose: "Compose" } }
    @ViewBuilder var image: some View {
        switch self {
        case .mark: Image("MenuBarIcon").renderingMode(.template).resizable().scaledToFit().frame(height: 13)
        case .text: Image(systemName: "text.alignleft")
        case .compose: Image(systemName: "square.and.pencil")
        }
    }
}


enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    var nativeAppearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}
