import KeyboardShortcuts
import SwiftUI

struct EditingShortcutSettings: View {
    let shortcuts: EditingShortcuts
    var actions: [EditingAction] = EditingAction.allCases

    var body: some View {
        ForEach(actions) { action in
            KeyboardShortcuts.Recorder(action.title, shortcut: Binding(
                get: { shortcuts.shortcut(for: action) },
                set: { shortcuts.set($0, for: action) }
            ))
            .shortcutValidation { shortcuts.validate($0, for: action) }
            .accessibilityIdentifier("editingShortcut.\(action.rawValue)")
        }
    }
}
