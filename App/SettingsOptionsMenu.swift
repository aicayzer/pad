import SwiftUI

/// A quiet native button that presents a native command menu.
struct SettingsOptionsMenu: NSViewRepresentable {
    let label: String
    let identifier: String
    let primaryTitle: String
    var primaryEnabled = true
    let primary: () -> Void
    let secondaryTitle: String
    var secondaryEnabled = true
    let secondary: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: label)!,
                              target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        (button.cell as? NSButtonCell)?.highlightsBy = []
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        context.coordinator.options = self
    }

    final class Coordinator: NSObject {
        var options: SettingsOptionsMenu?

        @objc func openMenu(_ button: NSButton) {
            guard let options else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let primary = NSMenuItem(title: options.primaryTitle, action: #selector(usePrimary), keyEquivalent: "")
            primary.target = self
            primary.isEnabled = options.primaryEnabled
            menu.addItem(primary)
            menu.addItem(.separator())
            let secondary = NSMenuItem(title: options.secondaryTitle, action: #selector(useSecondary), keyEquivalent: "")
            secondary.target = self
            secondary.isEnabled = options.secondaryEnabled
            menu.addItem(secondary)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
        }

        @objc func usePrimary() { options?.primary() }
        @objc func useSecondary() { options?.secondary() }
    }
}
