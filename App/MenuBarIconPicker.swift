import AppKit
import SwiftUI

/// AppKit applies template contrast separately to the button, menu rows, and highlighted row.
struct MenuBarIconPicker: NSViewRepresentable {
    @Binding var selection: MenuBarIcon
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setAccessibilityLabel("Menu bar icon")
        for icon in MenuBarIcon.allCases {
            button.menu?.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
            let item = button.lastItem!
            item.setAccessibilityLabel(icon.title)
            let image: NSImage?
            switch icon {
            case .mark: image = NSImage(named: "MenuBarIcon")?.copy() as? NSImage
            case .text: image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: icon.title)
            case .compose: image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: icon.title)
            }
            image?.isTemplate = true
            item.image = image
        }
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if let index = MenuBarIcon.allCases.firstIndex(of: selection) { button.selectItem(at: index) }
        button.isEnabled = isEnabled
        button.setAccessibilityValue(selection.title)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<MenuBarIcon>
        init(selection: Binding<MenuBarIcon>) { self.selection = selection }
        @objc func changed(_ sender: NSPopUpButton) {
            guard MenuBarIcon.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
            let icon = MenuBarIcon.allCases[sender.indexOfSelectedItem]
            selection.wrappedValue = icon
        }
    }
}
