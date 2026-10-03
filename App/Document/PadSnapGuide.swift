import AppKit

enum PadQuickPadPlacement {
    /// Center the window horizontally and one-third down the usable display.
    /// Tall windows stay within its bounds rather than covering the menu bar.
    static func frame(size: NSSize, in visible: NSRect) -> NSRect {
        let x = visible.midX - size.width / 2
        let preferredY = visible.maxY - visible.height / 3 - size.height / 2
        let y = max(visible.minY, min(preferredY, visible.maxY - size.height))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func isNear(_ frame: NSRect, target: NSRect) -> Bool {
        hypot(frame.midX - target.midX, frame.midY - target.midY) <= 80
    }
}

/// A transient, click-through preview, ordered behind the moving quick pad.
@MainActor
final class PadSnapGuide {
    private let panel: NSPanel
    private let view = GuideView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
    }

    func show(target: NSRect, near: Bool, below owner: NSWindow) {
        panel.appearance = owner.effectiveAppearance
        panel.level = owner.level
        panel.setFrame(target, display: false)
        view.isNear = near
        view.needsDisplay = true
        panel.order(.below, relativeTo: owner.windowNumber)
    }

    func hide() { panel.orderOut(nil) }

    private final class GuideView: NSView {
        var isNear = false

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                    xRadius: 16, yRadius: 16)
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.setLineDash([1.5, 5], count: 2, phase: 0)
            if isNear {
                NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
                path.fill()
            }
            NSColor.secondaryLabelColor.withAlphaComponent(0.65).setStroke()
            path.stroke()
        }
    }
}
