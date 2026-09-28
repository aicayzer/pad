import SwiftUI

struct AppCommands: Commands {
    let document: PadDocument
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Text File") { document.commandNew() }.keyboardShortcut("n", modifiers: .command)
            Button("Open File…") { Task { await document.openPicker() } }.keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { document.save() }.keyboardShortcut("s", modifiers: .command)
                .disabled(!document.isActive)
            Button("Save As…") { Task { await document.saveAs() } }.keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!document.isActive)
            Button("Share…") { document.share() }.disabled(!document.isActive)
        }
    }
}
