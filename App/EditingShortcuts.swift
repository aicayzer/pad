import AppKit
import KeyboardShortcuts
import Observation

enum EditingAction: String, CaseIterable, Identifiable, Codable {
    case newFile, open, save, saveAs

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newFile: "New Text File"
        case .open: "Open File"
        case .save: "Save"
        case .saveAs: "Save As"
        }
    }
    var defaultShortcut: KeyboardShortcuts.Shortcut {
        switch self {
        case .newFile: .init(.n, modifiers: .command)
        case .open: .init(.o, modifiers: .command)
        case .save: .init(.s, modifiers: .command)
        case .saveAs: .init(.s, modifiers: [.command, .shift])
        }
    }
}

@MainActor
@Observable
final class EditingShortcuts {
    private static let preferenceKey = "pad.editingShortcuts"
    private let defaults: UserDefaults
    private let globalShortcut: () -> KeyboardShortcuts.Shortcut?
    private var shortcuts: [EditingAction: KeyboardShortcuts.Shortcut]
    private(set) var error: String?

    init(defaults: UserDefaults = .standard,
         globalShortcut: @escaping () -> KeyboardShortcuts.Shortcut? = { KeyboardShortcuts.getShortcut(for: .pad) }) {
        self.defaults = defaults
        self.globalShortcut = globalShortcut
        if let data = defaults.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode([EditingAction: KeyboardShortcuts.Shortcut].self, from: data) {
            shortcuts = saved
        } else {
            shortcuts = Self.standardShortcuts
        }
    }

    private static var standardShortcuts: [EditingAction: KeyboardShortcuts.Shortcut] {
        Dictionary(uniqueKeysWithValues: EditingAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    var isDefault: Bool { shortcuts == Self.standardShortcuts }

    func shortcut(for action: EditingAction) -> KeyboardShortcuts.Shortcut? { shortcuts[action] }

    func action(for event: NSEvent) -> EditingAction? {
        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else { return nil }
        return EditingAction.allCases.first { shortcuts[$0] == shortcut }
    }

    func validate(_ shortcut: KeyboardShortcuts.Shortcut, for action: EditingAction) -> KeyboardShortcuts.ValidationResult {
        guard shortcut.modifiers.contains(.command), shortcut.toSwiftUI != nil else {
            return .disallow(reason: "Use a shortcut that includes Command.")
        }
        // Keep native editing, navigation, and application commands available.
        let reservedKeys: Set<KeyboardShortcuts.Key> = [.a, .c, .v, .x, .z, .f, .h, .m, .w, .q, .comma,
                                                       .leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward]
        if let key = shortcut.key, reservedKeys.contains(key) {
            return .disallow(reason: "This key is reserved for text editing or an app command.")
        }
        if globalShortcut() == shortcut {
            return .disallow(reason: "This shortcut already shows or hides Pad.")
        }
        if let other = EditingAction.allCases.first(where: { $0 != action && shortcuts[$0] == shortcut }) {
            return .disallow(reason: "This shortcut is already used by \(other.title).")
        }
        return .allow
    }

    func validateGlobal(_ shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
        if let action = EditingAction.allCases.first(where: { shortcuts[$0] == shortcut }) {
            return .disallow(reason: "This shortcut is already used by \(action.title).")
        }
        return .allow
    }

    @discardableResult
    func set(_ shortcut: KeyboardShortcuts.Shortcut?, for action: EditingAction) -> Bool {
        if let shortcut, case .disallow(let reason) = validate(shortcut, for: action) {
            error = reason
            return false
        }
        shortcuts[action] = shortcut
        persist()
        return true
    }

    func restoreDefaults() {
        if let global = globalShortcut(), Self.standardShortcuts.values.contains(global) {
            error = "Change the global shortcut before restoring these defaults."
            return
        }
        shortcuts = Self.standardShortcuts
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            defaults.set(data, forKey: Self.preferenceKey)
        }
        error = nil
    }
}
