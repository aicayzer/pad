import AppKit
import SwiftUI

/// File-window preview: AppKit owns the title, toolbar and standard window buttons.
@MainActor
final class PadFileToolbar: NSObject, NSToolbarDelegate {
    private let files: PadDocument
    private let formatting = NSToolbarItem.Identifier("pad-formatting")
    private let sharing = NSToolbarItem.Identifier("pad-sharing")
    private let saving = NSToolbarItem.Identifier("pad-saving")
    let toolbar = NSToolbar(identifier: "pad-file-toolbar")

    init(files: PadDocument) {
        self.files = files
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, formatting, sharing, saving]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case formatting:
            item.label = "Formatting"
            item.view = NSHostingView(rootView: FileFormattingControl(files: files))
        case sharing:
            item.label = "Share"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
            item.target = self
            item.action = #selector(share(_:))
        case saving:
            item.label = "Save"
            item.view = NSHostingView(rootView: FileSaveControl(files: files))
        default:
            return nil
        }
        return item
    }

    @objc private func share(_ sender: NSToolbarItem) {
        files.share(from: sender.view)
    }
}

private struct FileFormattingControl: View {
    let files: PadDocument

    var body: some View {
        Group {
            if files.currentFormat == .md, let editor = files.markdownEditor {
                Menu {
                    PadMarkdownToolbar(editor: editor).menuCommands
                } label: {
                    Image(systemName: "textformat")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(!editor.isReady)
                .modifier(PadMarkdownLinkPresenter(editor: editor))
                .help("Formatting")
            }
        }
        .frame(width: 32, height: 28)
    }
}

private struct FileSaveControl: View {
    let files: PadDocument

    var body: some View {
        Button("Save") { files.save() }
            .buttonStyle(.bordered)
            .disabled(!files.isDirty)
            .frame(width: 64, height: 28)
    }
}
