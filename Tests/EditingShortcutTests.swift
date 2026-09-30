import AppKit
import KeyboardShortcuts
import Testing
@testable import Pad

@MainActor
@Suite struct EditingShortcutTests {
    @Test func customAndRemovedShortcutsPersistOnlyInTheirSuite() throws {
        let firstName = "pad-shortcuts-\(UUID().uuidString)"
        let secondName = "pad-shortcuts-\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: firstName))
        let second = try #require(UserDefaults(suiteName: secondName))
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }
        let shortcuts = EditingShortcuts(defaults: first, globalShortcut: { nil })
        let replacement = KeyboardShortcuts.Shortcut(.b, modifiers: [.command, .shift])
        #expect(shortcuts.set(replacement, for: .newFile))
        #expect(shortcuts.set(nil, for: .open))
        let reloaded = EditingShortcuts(defaults: first, globalShortcut: { nil })
        #expect(reloaded.shortcut(for: .newFile) == replacement)
        #expect(reloaded.shortcut(for: .open) == nil)
        #expect(EditingShortcuts(defaults: second, globalShortcut: { nil }).isDefault)
        #expect((first.persistentDomain(forName: firstName) ?? [:]).keys.allSatisfy { !$0.hasPrefix("KeyboardShortcuts_") })
        reloaded.restoreDefaults()
        #expect(reloaded.isDefault)
        #expect(EditingShortcuts(defaults: first, globalShortcut: { nil }).isDefault)
    }

    @Test func conflictsAndNativeEditingCannotReplaceAssignments() throws {
        let name = "pad-shortcuts-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let global = KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .shift])
        let shortcuts = EditingShortcuts(defaults: defaults, globalShortcut: { global })
        #expect(!shortcuts.set(global, for: .newFile))
        #expect(!shortcuts.set(EditingAction.save.defaultShortcut, for: .newFile))
        let acceptedPaste = shortcuts.set(KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift]), for: .newFile)
        let acceptedTyping = shortcuts.set(KeyboardShortcuts.Shortcut(.b), for: .newFile)
        let acceptedClose = shortcuts.set(KeyboardShortcuts.Shortcut(.w, modifiers: .command), for: .newFile)
        let acceptedCopy = shortcuts.set(KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .shift]), for: .save)
        #expect(acceptedCopy == false)
        #expect(acceptedPaste == false)
        #expect(acceptedTyping == false)
        #expect(acceptedClose == false)
        #expect(shortcuts.isDefault)
        #expect(shortcuts.validateGlobal(EditingAction.save.defaultShortcut) != .allow)
        #expect(shortcuts.validateGlobal(global) == .allow)
        #expect(shortcuts.validateGlobal(.init(.c, modifiers: [.command, .shift])) != .allow)
    }

    @Test func restoreIsAtomicWhenGlobalNowUsesADefault() throws {
        let name = "pad-shortcuts-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var global: KeyboardShortcuts.Shortcut?
        let shortcuts = EditingShortcuts(defaults: defaults, globalShortcut: { global })
        let replacement = KeyboardShortcuts.Shortcut(.b, modifiers: .command)
        #expect(shortcuts.set(replacement, for: .newFile))
        global = EditingAction.newFile.defaultShortcut
        shortcuts.restoreDefaults()
        #expect(shortcuts.shortcut(for: .newFile) == replacement)
        #expect(shortcuts.error != nil)
    }

    @Test func existingCopyShortcutConflictsRemainAssigned() throws {
        let name = "pad-copy-conflict-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let copy = KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .shift])
        let original: [EditingAction: KeyboardShortcuts.Shortcut] = [.save: copy]
        defaults.set(try JSONEncoder().encode(original), forKey: "pad.editingShortcuts")
        let shortcuts = EditingShortcuts(defaults: defaults, globalShortcut: { nil })
        #expect(shortcuts.shortcut(for: .save) == copy)
        #expect(!shortcuts.copyAllShortcutAvailable)
        #expect(shortcuts.set(nil, for: .save))
        #expect(shortcuts.copyAllShortcutAvailable)
        #expect(!EditingShortcuts(defaults: defaults, globalShortcut: { copy }).copyAllShortcutAvailable)
    }

    @Test func eventRoutingUsesCustomBindingAndIgnoresOldBinding() throws {
        let name = "pad-shortcuts-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let shortcuts = EditingShortcuts(defaults: defaults, globalShortcut: { nil })
        #expect(shortcuts.set(.init(.b, modifiers: [.command, .shift]), for: .newFile))
        func event(_ key: KeyboardShortcuts.Key, _ character: String, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: UInt16(key.rawValue)))
        }
        #expect(shortcuts.action(for: try event(.b, "b", [.command, .shift])) == .newFile)
        #expect(shortcuts.action(for: try event(.n, "n", .command)) == nil)
        #expect(shortcuts.action(for: try event(.b, "b", [])) == nil)
        #expect(shortcuts.action(for: try event(.c, "c", .command)) == nil)
    }
}
