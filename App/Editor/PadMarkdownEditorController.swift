import AppKit
import Observation
import WebKit

enum PadMarkdownFormatCommand: String {
    case paragraph, heading, bold, italic, code, codeBlock, quote, bulletList, orderedList, link
}

enum PadMarkdownEditorError: LocalizedError {
    case notReady, documentChanged, invalidResponse, unavailable
    case script(String)

    var errorDescription: String? {
        switch self {
        case .notReady: "The Markdown editor is still loading. Please try again."
        case .documentChanged: "The document changed before its text could be read. Please try again."
        case .invalidResponse: "The Markdown editor could not return the document text. Your document has been kept open."
        case .unavailable: "The Markdown editor is unavailable. Your document has been kept open."
        case .script(let message): "The Markdown editor encountered a problem: \(message)"
        }
    }
}

@MainActor
@Observable
final class PadMarkdownEditorController: NSObject {
    private(set) var isReady = false
    private(set) var activeMarks: Set<String> = []
    var onChanged: (String, UUID) -> Void = { _, _ in }
    var onError: (any Error) -> Void = { _ in }
    var onReady: () -> Void = {}
    var accentOverride: NSColor? { didSet { applyAccent() } }
    var allowsFocus = true
    var showingLink = false

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var editorURL: URL?
    @ObservationIgnored private var pageReady = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var documentID: UUID?
    @ObservationIgnored private var pendingLoad: (markdown: String, reload: Bool)?
    @ObservationIgnored private var failure: (any Error)?
    @ObservationIgnored private var loadTask: Task<Void, any Error>?
    @ObservationIgnored private var pendingEvents: [NSEvent] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = false
        webView = PadMarkdownWebView(frame: .zero, configuration: configuration)
        super.init()
        (webView as? PadMarkdownWebView)?.onAttach = { [weak self] in self?.onReady() }
        configuration.userContentController.add(PadMarkdownMessageProxy(target: self), name: "host")
        configuration.userContentController.addUserScript(WKUserScript(source: """
            window.addEventListener('error', event => {
              webkit.messageHandlers.host.postMessage({type:'error', message:String(event.message)})
            });
            window.addEventListener('unhandledrejection', event => {
              webkit.messageHandlers.host.postMessage({type:'error', message:String(event.reason)})
            });
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        webView.isInspectable = true
        #endif
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") else {
            failure = PadMarkdownEditorError.unavailable
            return
        }
        editorURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func load(_ markdown: String, documentID: UUID) {
        replace(markdown, documentID: documentID, reload: false)
    }

    func reload(_ markdown: String, documentID: UUID) {
        replace(markdown, documentID: documentID, reload: true)
    }

    private func replace(_ markdown: String, documentID: UUID, reload: Bool) {
        generation += 1
        self.documentID = documentID
        activeMarks = []
        pendingEvents.removeAll()
        isReady = false
        pendingLoad = (markdown, reload)
        if pageReady { applyPendingLoad() }
    }

    private func applyPendingLoad() {
        guard let pendingLoad else { return }
        self.pendingLoad = nil
        let expectedGeneration = generation
        let function = pendingLoad.reload ? "reload" : "load"
        let script = "window.editor.\(function)(\(json(pendingLoad.markdown)), \(expectedGeneration))"
        loadTask = Task { @MainActor [weak self] in
            guard let self else { throw PadMarkdownEditorError.unavailable }
            do {
                _ = try await self.webView.evaluateJavaScript(script)
                guard self.generation == expectedGeneration else { throw PadMarkdownEditorError.documentChanged }
                self.failure = nil
                self.isReady = true
                self.onReady()

            } catch {
                if self.generation == expectedGeneration { self.report(error) }
                throw error
            }
        }
    }

    /// A nil result means the loaded source is unchanged, preserving its original formatting.
    func snapshot() async throws -> String? {
        let expectedGeneration = generation
        let deadline = ContinuousClock.now + .seconds(15)
        while !pageReady, failure == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            guard expectedGeneration == generation else { throw PadMarkdownEditorError.documentChanged }
        }
        if let loadTask { try await loadTask.value }
        guard expectedGeneration == generation else { throw PadMarkdownEditorError.documentChanged }
        if let failure { throw failure }
        guard isReady else { throw PadMarkdownEditorError.notReady }
        if !pendingEvents.isEmpty {
            guard let window = webView.window, window.isKeyWindow, allowsFocus else {
                throw PadMarkdownEditorError.notReady
            }
            window.makeFirstResponder(webView)
            _ = try await webView.evaluateJavaScript("window.editor.focus()")
            guard expectedGeneration == generation else { throw PadMarkdownEditorError.documentChanged }
            replayPendingEvents()
        }
        let result = try await webView.evaluateJavaScript("window.editor.markdown()")
        guard expectedGeneration == generation else { throw PadMarkdownEditorError.documentChanged }
        if result == nil || result is NSNull { return nil }
        guard let markdown = result as? String else { throw PadMarkdownEditorError.invalidResponse }
        return markdown
    }

    func focus() {
        guard allowsFocus, isReady, webView.window?.isKeyWindow == true else { return }
        webView.window?.makeFirstResponder(webView)
        let expectedGeneration = generation
        webView.evaluateJavaScript("window.editor.focus()") { [weak self] _, error in
            guard let self, expectedGeneration == self.generation else { return }
            if let error { self.report(error); return }
            self.replayPendingEvents()
        }
    }

    func enqueue(_ events: [NSEvent]) {
        pendingEvents.append(contentsOf: events)
        focus()
    }

    private func replayPendingEvents() {
        guard allowsFocus, isReady, let window = webView.window, window.isKeyWindow,
              let responder = window.firstResponder as? NSView,
              responder === webView || responder.isDescendant(of: webView) else { return }
        let expectedGeneration = generation
        let events = pendingEvents
        pendingEvents.removeAll()
        for event in events {
            guard expectedGeneration == generation, window.isKeyWindow else { break }
            window.sendEvent(event)
        }
    }

    func format(_ command: PadMarkdownFormatCommand, argument: String? = nil) {
        guard isReady else { return }
        call("format", json(command.rawValue), argument.map { json($0) } ?? "null")
        focus()
    }

    private func call(_ function: String, _ arguments: String...) {
        let expectedGeneration = generation
        webView.evaluateJavaScript("window.editor.\(function)(\(arguments.joined(separator: ",")))") { [weak self] _, error in
            guard let self, expectedGeneration == self.generation, let error else { return }
            self.report(error)
        }
    }

    private func json(_ value: some Encodable) -> String {
        // Encoding a string cannot fail; JSON escaping keeps document text out of executable code.
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    private func applyAccent() {
        guard pageReady else { return }
        webView.effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let color = (accentOverride ?? NSColor.controlAccentColor).usingColorSpace(.sRGB) else { return }
            let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
            let hex = String(format: "#%02X%02X%02X", channel(color.redComponent), channel(color.greenComponent), channel(color.blueComponent))
            call("setAccent", json(hex))
        }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            applyAccent()
            call("setKeymap", json([
                "bold": ["Mod-b"], "italic": ["Mod-i"], "code": ["Mod-e"],
                "heading1": ["Mod-Alt-1"], "heading2": ["Mod-Alt-2"],
                "heading3": ["Mod-Alt-3"], "paragraph": ["Mod-Alt-0"],
                "quote": ["Mod-Shift-b"], "bulletList": ["Mod-Alt-8"],
                "orderedList": ["Mod-Alt-7"], "codeBlock": ["Mod-Alt-c"],
            ]))
            applyPendingLoad()
        case "changed":
            guard let receivedGeneration = message["generation"] as? Int, receivedGeneration == generation,
                  let markdown = message["markdown"] as? String, let documentID else { return }
            onChanged(markdown, documentID)
        case "state":
            guard isReady else { return }
            if let receivedGeneration = message["generation"] as? Int, receivedGeneration != generation { return }
            activeMarks = Set(message["marks"] as? [String] ?? [])
        case "openLink":
            guard let href = message["href"] as? String, let url = URL(string: href),
                  let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        case "requestLink":
            showingLink = true
        case "copy":
            guard let text = message["text"] as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "error":
            report(PadMarkdownEditorError.script(message["message"] as? String ?? "Unknown error"))
        default: break
        }
    }

    private func report(_ error: any Error) {
        failure = error
        isReady = false
        onError(error)
    }
}

@MainActor
private final class PadMarkdownMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: PadMarkdownEditorController?
    init(target: PadMarkdownEditorController) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        target?.receive(message.body)
    }
}

extension PadMarkdownEditorController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url == editorURL ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { report(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { report(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        report(PadMarkdownEditorError.unavailable)
    }
}

@MainActor
private final class PadMarkdownWebView: WKWebView {
    var onAttach: () -> Void = {}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onAttach() }
    }
}
