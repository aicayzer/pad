import AppKit
import SwiftUI

/// A child panel lets feedback sit outside the editor without changing its size.
@MainActor
final class PadErrorBanner {
    private weak var owner: NSWindow?
    private let panel = ErrorPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
    private var message: String?

    init(owner: NSWindow) {
        self.owner = owner
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.title = "PadPad message"
    }

    func show(_ message: String?) {
        self.message = message
        guard let owner, let message, !message.isEmpty, owner.isVisible else {
            hide()
            return
        }
        let maximumWidth = max(100, owner.frame.width - 16)
        let font = NSFont.systemFont(ofSize: 13)
        let attributed = NSAttributedString(string: message, attributes: [.font: font])
        let width = min(maximumWidth, ceil(attributed.size().width) + 28)
        let bounds = attributed.boundingRect(with: NSSize(width: width - 28, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = max(40, ceil(bounds.height) + 24)
        panel.contentView = NSHostingView(rootView: ErrorBannerContent(message: message)
            .frame(width: width, height: height))
        panel.setContentSize(NSSize(width: width, height: height))
        panel.level = owner.level
        position()
        if panel.parent == nil { owner.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func position() {
        guard let owner, message != nil else { return }
        let size = panel.frame.size
        var y = owner.frame.minY - size.height - 8
        // Keep feedback readable when the editor is against the bottom edge.
        if let visible = owner.screen?.visibleFrame, y < visible.minY {
            y = min(owner.frame.maxY + 8, visible.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: owner.frame.midX - size.width / 2, y: y))
    }

    func hide() {
        if let parent = panel.parent { parent.removeChildWindow(panel) }
        panel.orderOut(nil)
    }
}

private final class ErrorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ErrorBannerContent: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Error: \(message)")
    }
}
