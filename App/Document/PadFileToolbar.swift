import AppKit
import Observation

/// Native toolbar items, without hosted controls or custom glass containers.
@MainActor
final class PadFileToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuDelegate {
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
        observeState()
    }

    private func observeState() {
        withObservationTracking {
            _ = files.isDirty
            _ = files.isBusy
            _ = files.markdownEditor?.isReady
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.toolbar.validateVisibleItems()
                self.observeState()
            }
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + (files.currentFormat == .md ? [formatting] : []) + [sharing, saving]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItem
        if identifier == formatting {
            let menuItem = NSMenuToolbarItem(itemIdentifier: identifier)
            menuItem.label = "Formatting"
            menuItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Formatting")
            menuItem.showsIndicator = false
            let menu = NSMenu(title: "Formatting")
            menu.delegate = self
            menuItem.menu = menu
            item = menuItem
        } else {
            item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self
            if identifier == sharing {
                item.label = "Share"
                item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
                item.action = #selector(share(_:))
            } else if identifier == saving {
                item.label = "Save"
                item.title = "Save"
                item.action = #selector(save(_:))
            } else { return nil }
        }
        item.isBordered = true
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard !files.isBusy else { return false }
        if item.itemIdentifier == saving { return files.isDirty }
        if item.itemIdentifier == formatting { return files.markdownEditor?.isReady == true }
        return true
    }

    @objc private func save(_ sender: NSToolbarItem) { files.save() }
    @objc private func share(_ sender: NSToolbarItem) { files.share(from: sender.view) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let headings = NSMenu(title: "Headings")
        for level in 1...3 {
            add("Heading \(level)", command: "heading", argument: String(level), to: headings,
                active: files.markdownEditor?.activeMarks.contains("heading\(level)") == true)
        }
        addSubmenu(headings, to: menu)
        let styles = NSMenu(title: "Text style")
        add("Bold", command: "bold", to: styles)
        add("Italic", command: "italic", to: styles)
        addSubmenu(styles, to: menu)
        menu.addItem(.separator())
        add("Link", command: "link", to: menu)
        add("Inline code", command: "code", to: menu)
        add("Code block", command: "codeBlock", to: menu)
        add("Quote", command: "quote", to: menu)
        menu.addItem(.separator())
        let lists = NSMenu(title: "Lists")
        add("Bulleted list", command: "bulletList", to: lists)
        add("Numbered list", command: "orderedList", to: lists)
        addSubmenu(lists, to: menu)
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func add(_ title: String, command: String, argument: String? = nil, to menu: NSMenu, active: Bool? = nil) {
        let item = NSMenuItem(title: title, action: #selector(format(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [command, argument ?? ""]
        item.state = (active ?? (files.markdownEditor?.activeMarks.contains(command) == true)) ? .on : .off
        menu.addItem(item)
    }

    @objc private func format(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String],
              let command = PadMarkdownFormatCommand(rawValue: values[0]),
              let editor = files.markdownEditor else { return }
        if command == .link { editor.showingLink = true }
        else { editor.format(command, argument: values[1].isEmpty ? nil : values[1]) }
    }
}
