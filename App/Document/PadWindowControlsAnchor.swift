import AppKit
import Observation
import SwiftUI

/// The native buttons stay where AppKit puts them. The custom header follows.
@MainActor
@Observable
final class PadFileHeaderMetrics {
    var height: CGFloat = 52
    var titleInset: CGFloat = 84
}

struct PadWindowControlsAnchor: NSViewRepresentable {
    var metrics: PadFileHeaderMetrics?

    func makeNSView(context: Context) -> HeaderAnchor {
        let view = HeaderAnchor()
        view.metrics = metrics
        return view
    }

    func updateNSView(_ view: HeaderAnchor, context: Context) {
        view.metrics = metrics
        view.scheduleMeasurement()
    }

    final class HeaderAnchor: NSView {
        weak var metrics: PadFileHeaderMetrics?
        private var measurementScheduled = false
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let window, metrics != nil {
                for name in [NSWindow.didResizeNotification, NSWindow.didUpdateNotification,
                             NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                        queue: .main) { [weak self] _ in
                            MainActor.assumeIsolated { self?.scheduleMeasurement() }
                        })
                }
            }
            scheduleMeasurement()
        }

        override func layout() {
            super.layout()
            scheduleMeasurement()
        }

        func scheduleMeasurement() {
            guard metrics != nil, !measurementScheduled else { return }
            measurementScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.measurementScheduled = false
                self.measureHeader()
            }
        }

        private func measureHeader() {
            guard let window, let content = window.contentView, let metrics,
                  let close = window.standardWindowButton(.closeButton), !close.isHidden,
                  let zoom = window.standardWindowButton(.zoomButton) else { return }
            let closeRect = content.convert(close.bounds, from: close)
            let zoomRect = content.convert(zoom.bounds, from: zoom)
            let centerFromTop = content.isFlipped ? closeRect.midY - content.bounds.minY
                : content.bounds.maxY - closeRect.midY
            guard centerFromTop > 0, centerFromTop < 80 else { return }
            let height = centerFromTop * 2
            let inset = zoomRect.maxX - content.bounds.minX + 14
            if abs(metrics.height - height) > 0.5 { metrics.height = height }
            if abs(metrics.titleInset - inset) > 0.5 { metrics.titleInset = inset }
        }

        isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
