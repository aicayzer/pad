import AppKit
import SwiftUI

/// File-window preview: AppKit owns the title, toolbar and standard window buttons.
@MainActor
final class PadFileToolbar: NSObject, NSToolbarDelegate {
    private let files: PadDocument
    private let actions = NSToolbarItem.Identifier("pad-file-actions")
    let toolbar = NSToolbar(identifier: "pad-file-toolbar")

    init(files: PadDocument) {
        self.files = files
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, actions]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == actions else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Document actions"
        let width: CGFloat = files.currentFormat == .md ? 152 : 108
        let host = NSHostingView(rootView: FileToolbarControls(files: files, share: { [weak self] in
            guard let self else { return }
            files.share(from: toolbar.items.first(where: { $0.itemIdentifier == actions })?.view)
        }).frame(width: width, height: 28))
        // The toolbar owns this fixed-size slot. Do not let hosting constraints
        // expand the native glass group or assign different baselines to its controls.
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: 28)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: width),
            host.heightAnchor.constraint(equalToConstant: 28)
        ])
        item.view = host
        return item
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

private struct FileToolbarControls: View {
    let files: PadDocument
    let share: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if files.currentFormat == .md {
                FileFormattingControl(files: files)
            }
            Button(action: share) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 28, height: 28)
            }
            .help("Share")
            .accessibilityLabel("Share")
            Button("Save") { files.save() }
                .disabled(!files.isDirty)
                .frame(width: 52, height: 28)
        }
        .buttonStyle(.plain)
    }
}
