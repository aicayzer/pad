import AppKit
import SwiftUI

/// Align native window controls with the actual custom header, without replacing them.
struct PadWindowControlsAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> HeaderAnchor { HeaderAnchor() }
    func updateNSView(_ view: HeaderAnchor, context: Context) { view.scheduleAlignment() }

    final class HeaderAnchor: NSView {
        private var alignmentScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleAlignment()
        }

        override func layout() {
            super.layout()
            scheduleAlignment()
        }

        func scheduleAlignment() {
            guard !alignmentScheduled else { return }
            alignmentScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.alignmentScheduled = false
                self.alignControls()
            }
        }

        private func alignControls() {
            guard let window, bounds.height > 0 else { return }
            let midpoint = NSPoint(x: bounds.midX, y: bounds.midY)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(kind), !button.isHidden,
                      let parent = button.superview else { continue }
                let center = parent.convert(midpoint, from: self)
                let y = center.y - button.frame.height / 2
                if abs(button.frame.origin.y - y) > 0.25 {
                    button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
                }
            }
        }
    }
}
