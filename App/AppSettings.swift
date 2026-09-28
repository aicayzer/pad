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
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    var customAccent: String { didSet { defaults.set(customAccent, forKey: "customAccent") } }
    private(set) var policyPending = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        menuBarItem = defaults.object(forKey: "menuBarItem") as? Bool ?? true
        menuBarIcon = MenuBarIcon(rawValue: defaults.string(forKey: "menuBarIcon") ?? "") ?? .mark
        accent = AccentChoice(rawValue: defaults.string(forKey: "accent") ?? "") ?? .standard
        customAccent = defaults.string(forKey: "customAccent") ?? "BEBAFC"
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

    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { policyPending = false; return }
        // Changing policy while active can steal focus from the settings being edited.
        guard !NSApp.isActive else { policyPending = true; return }
        NSApp.setActivationPolicy(policy)
        policyPending = false
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
    var title: String { switch self { case .mark: "Pad"; case .text: "Text"; case .compose: "Compose" } }
    @ViewBuilder var image: some View {
        switch self {
        case .mark: Image("MenuBarIcon").renderingMode(.template).resizable().scaledToFit().frame(height: 13)
        case .text: Image(systemName: "text.alignleft")
        case .compose: Image(systemName: "square.and.pencil")
        }
    }
}
