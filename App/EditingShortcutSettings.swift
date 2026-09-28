import KeyboardShortcuts
import SwiftUI

struct EditingShortcutSettings: View {
    let shortcuts: EditingShortcuts

    var body: some View {
        ForEach(EditingAction.allCases) { action in
            KeyboardShortcuts.Recorder(action.title, shortcut: Binding(
                get: { shortcuts.shortcut(for: action) },
                set: { shortcuts.set($0, for: action) }
            ))
            .shortcutValidation { shortcuts.validate($0, for: action) }
            .accessibilityIdentifier("editingShortcut.\(action.rawValue)")
        }
        Button("Restore Defaults") { shortcuts.restoreDefaults() }
            .disabled(shortcuts.isDefault)
        if let error = shortcuts.error {
            Text(error).foregroundStyle(.red).font(.caption)
        }
    }
}
