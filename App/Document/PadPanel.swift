import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

@MainActor
private final class PadShareAnchor {
    weak var view: NSView?
}

private struct PadShareAnchorView: NSViewRepresentable {
    let anchor: PadShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

final class PadPanel: NSPanel {
    private let files: PadDocument
    private let quit: @MainActor () -> Void
    private var previousFrame: NSRect?
    private let pendingTitleInput = OverlayInputResponder()
    private let pendingEditorInput = MarkdownInputBuffer()
    private var editorFocusScheduled = false

    var pendingEditorEventCount: Int { pendingEditorInput.eventCount }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(files: PadDocument, quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.files = files
        self.quit = quit
        super.init(contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = files.floating ? .floating : .normal
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // AppKit draws outside the window; a SwiftUI shadow gets clipped at the hosting bounds.
        hasShadow = true
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: PadView(files: files, prepareTitleFocus: { [weak self] in
            guard let self else { return }
            pendingTitleInput.discardEvents()
            makeFirstResponder(pendingTitleInput)
        }).environment(files.appSettings ?? AppSettings())
            // Hosting derives the native minimum from the content's constraints.
            .frame(minWidth: 520, minHeight: 320))
        pendingEditorInput.attach(to: self)
        pendingEditorInput.onInput = { [weak self] in self?.requestEditorFocus() }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        center()
    }

    @objc private func applicationBecameActive() { requestEditorFocus() }

    func requestEditorFocus() {
        guard !files.onboarding.isPresented else { return }
        guard !editorFocusScheduled else { return }
        editorFocusScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.editorFocusScheduled = false
            guard !self.files.onboarding.isPresented else { return }
            guard self.isKeyWindow, self.isVisible, !self.files.settingsPresented else { return }
            guard !self.pendingEditorInput.isComposing else { return }
            let awaitingEditor = self.firstResponder === self.pendingEditorInput || self.firstResponder === self
            if self.files.currentFormat == .md {
                guard let editor = self.files.markdownEditor else { return }
                // Replacing the document can temporarily buffer input while DOM focus catches up.
                guard awaitingEditor || editor.ownsFirstResponder else { return }
                editor.enqueueInputs(self.pendingEditorInput.takeInputs())
                return
            }
            guard awaitingEditor, let content = self.contentView,
                  let editor = self.editor(in: content), editor.isEditable else { return }
            self.makeFirstResponder(editor)
        }
    }

    func prepareMarkdownSnapshot() {
        guard files.currentFormat == .md, let editor = files.markdownEditor else { return }
        editor.hasExternalMarkedText = { [weak self] in self?.pendingEditorInput.isComposing == true }
        guard !pendingEditorInput.isComposing, pendingEditorInput.eventCount > 0 else { return }
        editor.enqueueInputs(pendingEditorInput.takeInputs())
    }

    func prepareOnboarding() {
        pendingTitleInput.discardEvents()
        pendingEditorInput.discardEvents()
        makeFirstResponder(nil)
    }

    func resumeEditor() {
        guard !files.onboarding.isPresented else { return }
        pendingEditorInput.attach(to: self)
        makeFirstResponder(pendingEditorInput)
        files.isActive = true
        requestEditorFocus()
    }

    private func editor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, !(editor is MarkdownInputBuffer), !editor.isFieldEditor { return editor }
        for child in view.subviews {
            if let editor = editor(in: child) { return editor }
        }
        return nil
    }

    override func sendEvent(_ event: NSEvent) {
        if handleOnboardingNavigation(event) { return }
        if !files.onboarding.isPresented, files.currentFormat == .md, firstResponder !== pendingEditorInput,
           files.markdownEditor?.capturePendingInput(event) == true { return }
        super.sendEvent(event)
    }

    // Onboarding may be summoned as a nonactivating panel before SwiftUI has a
    // focused control. Handle its navigation here, independently of button focus.
    private func handleOnboardingNavigation(_ event: NSEvent) -> Bool {
        guard files.onboarding.isPresented, event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        let key = Int(event.keyCode)
        guard [kVK_Return, kVK_LeftArrow, kVK_RightArrow, kVK_Space].contains(key) else { return false }
        guard !event.isARepeat else { return true }
        let shortcut = KeyboardShortcuts.getShortcut(for: .pad)
        // A configured bare navigation key belongs to the real global-shortcut
        // callback. It must never also navigate or finish on its local key-down.
        if shortcut?.modifiers.isEmpty == true,
           (key == kVK_Return && shortcut?.key == .return ||
            key == kVK_LeftArrow && shortcut?.key == .leftArrow ||
            key == kVK_RightArrow && shortcut?.key == .rightArrow ||
            key == kVK_Space && shortcut?.key == .space) { return true }
        switch key {
        case kVK_Space:
            // Editing-style focus keeps Tab navigation available independently of
            // macOS's all-controls preference; Space activates that focused action.
            switch files.onboarding.focusedControl {
            case .close: files.close()
            case .next: files.onboarding.startPractice()
            case .back: files.onboarding.showIntroduction()
            case .skip: files.finishOnboarding(includeExample: false)
            case .done:
                if files.onboarding.practiceCount > 0 { files.finishOnboarding(includeExample: true) }
            case nil: return false
            }
        case kVK_LeftArrow: files.onboarding.showIntroduction()
        case kVK_RightArrow: files.onboarding.startPractice()
        default:
            if files.onboarding.stage == .intro {
                files.onboarding.startPractice()
            } else if files.onboarding.practiceCount > 0 {
                files.finishOnboarding(includeExample: true)
            }
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let action = files.editingShortcuts.action(for: event) {
            guard !files.onboarding.isPresented else { return true }
            switch action {
            case .newFile: files.commandNew()
            case .open: Task { await files.openPicker() }
            case .save: files.save()
            case .saveAs: Task { await files.saveAs() }
            }
            return true
        }
        if files.editingShortcuts.copyAllShortcutAvailable,
           modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            if !files.onboarding.isPresented { Task { await files.copyAllContents() } }
            return true
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            case "w": files.close()
            case ",":
                files.settingsPresented = true
                files.showSettings()
            case "q": quit()
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { files.close() }

    override func close() { files.close() }

    func toggleExpanded() {
        if let previousFrame {
            setFrame(previousFrame, display: true, animate: true)
            self.previousFrame = nil
        } else if let screen = screen ?? NSScreen.main {
            previousFrame = frame
            setFrame(screen.visibleFrame.insetBy(dx: 24, dy: 24), display: true, animate: true)
        }
    }

    override func becomeKey() {
        super.becomeKey()
        files.settingsPresented = false
        guard !files.onboarding.isPresented else {
            files.isActive = false
            return
        }
        if !(firstResponder is NSTextView), files.markdownEditor?.ownsFirstResponder != true {
            pendingEditorInput.attach(to: self)
            makeFirstResponder(pendingEditorInput)
        }
        files.isActive = true
        requestEditorFocus()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        if result, let editor = responder as? NSTextView,
           !(editor is MarkdownInputBuffer), !editor.isFieldEditor {
            // SwiftUI must finish mounting the editor and its binding before replaying input.
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, let editor, self.isKeyWindow, self.firstResponder === editor else { return }
                for input in self.pendingEditorInput.takeInputs() {
                    guard self.isKeyWindow, self.firstResponder === editor else { break }
                    switch input {
                    case .text(let text): editor.insertText(text, replacementRange: editor.selectedRange())
                    case .key(let event): self.sendEvent(event)
                    }
                }
            }
        }
        return result
    }

    override func resignKey() {
        super.resignKey()
        pendingTitleInput.discardEvents()
        files.isActive = false
        files.lostFocus()
    }

}

private struct PadView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings
    @Bindable var files: PadDocument
    let prepareTitleFocus: () -> Void
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var renamedDocument: UUID?
    @FocusState private var editing: Bool
    @State private var shareAnchor = PadShareAnchor()
    @State private var showingFormatting = false
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .pad)

    var body: some View {
        ZStack {
            if files.onboarding.isPresented {
                PadOnboardingView(onboarding: files.onboarding, shortcut: shortcut,
                                  onContinue: { files.finishOnboarding(includeExample: true) },
                                  onSkip: { files.finishOnboarding(includeExample: false) },
                                  onClose: { files.close() })
            } else {
                editorContent
            }
        }
        .tint(settings.accentColor)
        .onAppear {
            let action = openSettings
            files.showSettings = { action() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            shortcut = KeyboardShortcuts.getShortcut(for: .pad)
        }
        .onChange(of: files.onboarding.isPresented) { _, presented in
            if presented { editing = false; renaming = false; showingFormatting = false }
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let centerWidth: CGFloat = showingFormatting && files.currentFormat == .md
                    ? (geometry.size.width >= 820 ? 280 : geometry.size.width >= 700 ? 144 : 36) : 0
                let sideWidth = (geometry.size.width - centerWidth) / 2 - 12
                let titleSpace = max(40, sideWidth - 88)
                ZStack {
                    HStack(spacing: 6) {
                        Button { files.close() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .frame(width: 22, height: 26)
                        }
                        .accessibilityLabel("Close PadPad")
                        HStack(spacing: 5) {
                            if renaming {
                                HStack(spacing: 2) {
                                    OverlaySearchField(placeholder: "Name", text: $titleDraft, fontSize: 14,
                                                       isCurrent: { renaming && files.isActive && renamedDocument == files.documentID },
                                                       submit: {
                                                           guard renamedDocument == files.documentID else { return }
                                                           if files.rename(to: titleDraft) { finishRename() }
                                                       }, dismiss: finishRename, blur: { renaming = false })
                                        .frame(width: min(titleWidth(titleDraft, weight: .regular) + 6, max(40, titleSpace - 36)))
                                    Text(".\(files.url?.pathExtension ?? files.currentFormat.rawValue)")
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                                .background(.background, in: RoundedRectangle(cornerRadius: 5))
                            } else {
                                Text(files.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .accessibilityIdentifier("documentTitle")
                                    .help("Double-click to rename")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .onTapGesture(count: 2) {
                                        editing = false
                                        titleDraft = files.editableName
                                        renamedDocument = files.documentID
                                        prepareTitleFocus()
                                        renaming = true
                                    }
                                    .simultaneousGesture(WindowDragGesture())
                            }

                            if files.isDirty {
                                Circle().frame(width: 6, height: 6).foregroundStyle(.secondary)
                                    .accessibilityLabel("Unsaved changes")
                                    .accessibilityIdentifier("unsavedIndicator")
                            }
                        }
                        .frame(maxWidth: titleSpace + 12, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        DevelopmentBadge().fixedSize()
                        Spacer(minLength: 0)
                        HStack(spacing: 2) {
                            if files.currentFormat == .md, let editor = files.markdownEditor {
                                Button {
                                    showingFormatting.toggle()
                                    editor.focus()
                                } label: {
                                    Image(systemName: "textformat").frame(width: 16)
                                }
                                .buttonStyle(PadToolbarButtonStyle(selected: showingFormatting))
                                .accessibilityLabel("Formatting")
                                .accessibilityIdentifier("formattingToggle")
                                .accessibilityValue(showingFormatting ? "Shown" : "Hidden")
                                .accessibilityAddTraits(showingFormatting ? .isSelected : [])
                                .help(showingFormatting ? "Hide formatting" : "Show formatting")
                                .disabled(!editor.isReady)
                                .modifier(PadMarkdownLinkPresenter(editor: editor))
                            }
                            actionIcon("square.and.arrow.up", label: "Share", verticalOffset: -1) {
                                files.share(from: shareAnchor.view)
                            }
                            .background(PadShareAnchorView(anchor: shareAnchor).allowsHitTesting(false))

                        }
                        .fixedSize()
                        Button("Save") { files.save() }
                            .buttonStyle(PadToolbarButtonStyle(primary: true))
                            .fixedSize()
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                    if showingFormatting, files.currentFormat == .md, let editor = files.markdownEditor {
                        PadMarkdownToolbar(editor: editor)
                            .frame(width: centerWidth)
                    }
                }
                .frame(width: geometry.size.width, height: 38)
            }
            .frame(height: 38)
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { files.expand() }
                    .simultaneousGesture(WindowDragGesture())
            }

            VStack(spacing: 0) {
                if files.currentFormat == .md {
                    if let editor = files.markdownEditor {
                        PadMarkdownEditorView(editor: editor)
                            .onChange(of: settings.accentColor, initial: true) {
                                editor.accentOverride = NSColor(settings.accentColor)
                            }
                            .onChange(of: editor.showingLink) {
                                if !editor.showingLink { files.lostFocus() }
                            }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear { files.mountMarkdownEditor() }
                    }
                } else {
                    PadPlainTextEditorView(text: $files.text)
                        .id(files.documentID)
                        .background(EditorFocusMount())
                        .focused($editing)
                        .padding(10)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Text(files.error ?? files.notice ?? " ")
                        .foregroundStyle(files.error == nil ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(files.error == nil && files.notice == nil)
                    if settings.showFormatToggle {
                        Button(files.currentFormat.title) {
                            Task { await files.toggleFormat() }
                        }
                        .buttonStyle(PadFormatButtonStyle())
                        .accessibilityIdentifier("documentFormat")
                        .accessibilityLabel(files.currentFormat == .md ? "Markdown" : "Plain text")
                        .accessibilityValue(files.currentFormat.title)
                        .help(files.currentFormat == .md ? "Switch to plain text" : "Switch to Markdown")
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        // AppKit owns the outside shape, shadow and resize border as one native rounded frame.
        .glassEffect(.regular, in: .rect)
        .ignoresSafeArea()
        .tint(settings.accentColor)
        .disabled(files.isBusy)
        .defaultFocus($editing, true)
        .onAppear {
            let action = openSettings
            files.showSettings = { action() }
        }
        .onChange(of: files.documentID) { finishRename() }
        .onChange(of: files.currentFormat) { showingFormatting = false }
        .onChange(of: files.isActive, initial: true) {
            if files.isActive {
                if !renaming { editing = true }
            } else {
                renaming = false
            }
        }
    }

    private func titleWidth(_ text: String, weight: NSFont.Weight) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: weight)]).width
    }

    private func finishRename() {
        renaming = false
        editing = files.isActive
        if files.isActive { files.markdownEditor?.focus() }
    }

    private func actionIcon(_ symbol: String, label: String, verticalOffset: CGFloat,
                            perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .frame(width: 16)
                .offset(y: verticalOffset)
        }
        .buttonStyle(PadToolbarButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct PadFormatButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 24, minHeight: 16)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hovered || configuration.isPressed ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onHover { hovered = $0 }
    }
}

private struct PadToolbarButtonStyle: ButtonStyle {
    var primary = false
    var selected = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary || selected ? .primary : .secondary)
            .frame(height: 16)
            .padding(.horizontal, primary ? 14 : 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(primary || hovered || configuration.isPressed ? 0.1 : 0), in: Capsule())
            .contentShape(Capsule())
            .onHover { hovered = $0 }
    }
}

// The native editor can mount after SwiftUI's initial focus request has already run.
private struct EditorFocusMount: NSViewRepresentable {
    func makeNSView(context: Context) -> MountView { MountView() }

    func updateNSView(_ view: MountView, context: Context) { view.requestFocus() }

    final class MountView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFocus()
        }

        override func layout() {
            super.layout()
            requestFocus()
        }

        func requestFocus() { (window as? PadPanel)?.requestEditorFocus() }
    }
}
