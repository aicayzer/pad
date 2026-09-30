import SwiftUI

struct AppCommands: Commands {
    let document: PadDocument
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Draft") { document.commandNew() }.keyboardShortcut(document.editingShortcuts.shortcut(for: .newFile)?.toSwiftUI)
            Button("Open File…") { Task { await document.openPicker() } }.keyboardShortcut(document.editingShortcuts.shortcut(for: .open)?.toSwiftUI)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { document.save() }.keyboardShortcut(document.editingShortcuts.shortcut(for: .save)?.toSwiftUI)
                .disabled(!document.isActive)
            Button("Save As…") { Task { await document.saveAs() } }.keyboardShortcut(document.editingShortcuts.shortcut(for: .saveAs)?.toSwiftUI)
                .disabled(!document.isActive)
            Button("Share…") { document.share() }.disabled(!document.isActive)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy All Contents") { Task { await document.copyAllContents() } }
                .keyboardShortcut(document.editingShortcuts.copyAllShortcutAvailable ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
                .disabled(!document.isActive || document.isBusy || document.onboarding.isPresented)
            Button("Copy as Markdown") { Task { await document.copyAllContents(asMarkdown: true) } }
                .disabled(!document.isActive || document.isBusy || document.onboarding.isPresented || document.currentFormat != .md)
        }
        CommandGroup(replacing: .help) {
            Button("Show PadPad Introduction") { Task { await document.restartOnboarding() } }
        }
    }
}
