import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock"); if !defersActivationPolicy { applyActivationPolicy() } } }
    var menuBarItem: Bool { didSet { defaults.set(menuBarItem, forKey: "menuBarItem") } }
    var menuBarIcon: MenuBarIcon { didSet { defaults.set(menuBarIcon.rawValue, forKey: "menuBarIcon") } }
    var showFormatToggle: Bool { didSet { defaults.set(showFormatToggle, forKey: "showFormatToggle") } }
    var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    var customAccent: String { didSet { defaults.set(customAccent, forKey: "customAccent") } }
    private(set) var activationPolicyError: String?
    private(set) var isChangingActivationPolicy = false
    @ObservationIgnored private var activationGeneration = 0
    @ObservationIgnored private weak var activationWindow: NSWindow?
    @ObservationIgnored private var defersActivationPolicy = false
    @ObservationIgnored private var activationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var departureMonitor: Any?
    @ObservationIgnored private var localDepartureMonitor: Any?
    @ObservationIgnored private var activationCleanup: Task<Void, Never>?
    @ObservationIgnored private var requestedReactivation = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInDock = defaults.object(forKey: "showInDock") == nil ? true : defaults.bool(forKey: "showInDock")
        menuBarItem = defaults.object(forKey: "menuBarItem") == nil ? true : defaults.bool(forKey: "menuBarItem")
        menuBarIcon = MenuBarIcon(rawValue: defaults.string(forKey: "menuBarIcon") ?? "") ?? .mark
        showFormatToggle = defaults.object(forKey: "showFormatToggle") == nil ? true : defaults.bool(forKey: "showFormatToggle")
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        accent = AccentChoice(rawValue: defaults.string(forKey: "accent") ?? "") ?? .standard
        customAccent = defaults.string(forKey: "customAccent") ?? "BEBAFC"
    }

    var access: AppAccess { AppAccess(showInDock: showInDock, menuBarItem: menuBarItem) }

    func setAccess(_ access: AppAccess, hasGlobalShortcut: Bool, from window: NSWindow? = nil) {
        guard access != .shortcutOnly || hasGlobalShortcut else { return }
        cancelActivationTransition()
        defersActivationPolicy = window != nil
        // Establish the menu entry point before hiding the Dock icon.
        if access.menuBarItem { menuBarItem = true }
        if showInDock != access.showInDock { showInDock = access.showInDock }
        if !access.menuBarItem { menuBarItem = false }
        guard let window else { return }
        let generation = activationGeneration
        // Picker actions run inside menu tracking; wait for its activation restoration to finish.
        RunLoop.main.perform(inModes: [.default]) { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, self.activationGeneration == generation else { return }
                self.defersActivationPolicy = false
                self.applyActivationPolicy(restoring: window)
            }
        }
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

    func applyActivationPolicy(restoring window: NSWindow? = nil) {
        guard !defersActivationPolicy else { return }
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { activationPolicyError = nil; return }
        let restoreWindow = window ?? NSApp.keyWindow
        cancelActivationTransition()
        if NSApp.isActive, let restoreWindow, restoreWindow.isVisible {
            beginActivationTransition(window: restoreWindow)
        }
        let applied = NSApp.setActivationPolicy(policy)
        activationPolicyError = applied || NSApp.activationPolicy() == policy
            ? nil : "Could not update Dock visibility. Try changing the setting again."
        if !applied { cancelActivationTransition() }
    }

    private func beginActivationTransition(window: NSWindow) {
        activationWindow = window
        isChangingActivationPolicy = true
        let generation = activationGeneration
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            activationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let name = notification.name
                let changedWindow = notification.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let self, self.activationGeneration == generation else { return }
                    self.activationChanged(name, window: changedWindow, generation: generation)
                }
            })
        }
        // A deliberate switch or click elsewhere cancels restoration rather than stealing focus back.
        departureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelActivationTransition() }
        }
        localDepartureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown || event.window !== self?.activationWindow {
                    self?.cancelActivationTransition()
                }
            }
            return event
        }
        // This bounds observer lifetime only; it never retries activation or declares success.
        activationCleanup = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, self.activationGeneration == generation else { return }
            self.cancelActivationTransition()
        }
    }

    private func activationChanged(_ name: Notification.Name, window changedWindow: NSWindow?, generation: Int) {
        guard let window = activationWindow, window.isVisible else { cancelActivationTransition(); return }
        if name == NSWindow.willCloseNotification, changedWindow === window {
            cancelActivationTransition()
        } else if name == NSApplication.didResignActiveNotification, !requestedReactivation {
            requestedReactivation = true
            RunLoop.main.perform(inModes: [.default]) { [weak self, weak window] in
                MainActor.assumeIsolated {
                    guard let self, self.activationGeneration == generation, let window, window.isVisible else { return }
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                }
            }
        } else if requestedReactivation, NSApp.isActive, window.isKeyWindow {
            cancelActivationTransition()
        }
    }

    private func cancelActivationTransition() {
        defersActivationPolicy = false
        activationGeneration += 1
        activationCleanup?.cancel()
        activationCleanup = nil
        activationObservers.forEach(NotificationCenter.default.removeObserver)
        activationObservers.removeAll()
        if let departureMonitor { NSEvent.removeMonitor(departureMonitor) }
        if let localDepartureMonitor { NSEvent.removeMonitor(localDepartureMonitor) }
        departureMonitor = nil
        localDepartureMonitor = nil
        activationWindow = nil
        requestedReactivation = false
        isChangingActivationPolicy = false
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
