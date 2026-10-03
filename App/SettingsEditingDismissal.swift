import SwiftUI

/// Ends numeric editing on clicks outside the field without consuming the click.
struct SettingsEditingDismissal: NSViewRepresentable {
    let isEditing: Bool
    let dismiss: () -> Void

    func makeNSView(context: Context) -> DismissalView { DismissalView() }

    func updateNSView(_ view: DismissalView, context: Context) {
        view.isEditing = isEditing
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: DismissalView, coordinator: ()) {
        view.removeMonitor()
    }

    final class DismissalView: NSView {
        var isEditing = false
        var dismiss: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, self.isEditing, let window = self.window,
                      event.window === window,
                      let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                      let field = editor.delegate as? NSTextField else { return event }
                let point = field.convert(event.locationInWindow, from: nil)
                guard !field.bounds.contains(point) else { return event }
                // Finish through the responder chain so the formatter commits the value.
                if window.makeFirstResponder(nil) { self.dismiss?() }
                return event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
