import AppKit

/// Keeps the native input context alive while the document editor is mounting.
@MainActor
final class MarkdownInputBuffer: NSTextView {
    enum Input {
        case text(String)
        case key(NSEvent)
    }

    private var inputs: [Input] = []
    private var interpretingEvent: NSEvent?
    private var committing = false
    private var awaitingCommit = false
    private var interpretationRevision = 0
    var onInput: () -> Void = {}
    var eventCount: Int { inputs.count }
    var isComposing: Bool { hasMarkedText() || awaitingCommit }

    init() {
        super.init(frame: .zero, textContainer: nil)
        isRichText = false
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(to window: NSWindow) {
        guard let content = window.contentView, superview !== content else { return }
        removeFromSuperview()
        content.addSubview(self)
    }

    override func resignFirstResponder() -> Bool {
        // DOM focus can arrive while AppKit is still composing the buffered input.
        guard !isComposing else { return false }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        interpretingEvent = event
        defer { interpretingEvent = nil }
        if event.modifierFlags.contains(.command) {
            inputs.append(.key(event))
            onInput()
        } else {
            // AppKit, not NSEvent.characters, resolves dead keys and marked-text input.
            let revision = interpretationRevision
            interpretKeyEvents([event])
            // Dead keys can be consumed without marked text or an insertion callback.
            awaitingCommit = interpretationRevision == revision
            onInput()
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String) ?? ""
        interpretationRevision += 1
        awaitingCommit = false
        committing = true
        super.insertText(insertString, replacementRange: replacementRange)
        committing = false
        if !text.isEmpty { inputs.append(.text(text)) }
        string = ""
        onInput()
    }

    override func unmarkText() {
        let marked = hasMarkedText()
        super.unmarkText()
        guard marked, !committing else { return }
        interpretationRevision += 1
        awaitingCommit = false
        if !string.isEmpty { inputs.append(.text(string)) }
        string = ""
        onInput()
    }

    override func doCommand(by selector: Selector) {
        interpretationRevision += 1
        awaitingCommit = false
        if hasMarkedText() {
            super.doCommand(by: selector)
        } else if let event = interpretingEvent {
            inputs.append(.key(event))
            onInput()
        }
    }

    func takeInputs() -> [Input] {
        defer { inputs.removeAll() }
        return inputs
    }

    func discardEvents() {
        awaitingCommit = false
        committing = true
        inputContext?.discardMarkedText()
        super.unmarkText()
        string = ""
        committing = false
        inputs.removeAll()
    }
}
