import AppKit
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
    private let pendingEditorInput = OverlayInputResponder()
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
        minSize = NSSize(width: 520, height: 320)
        contentView = NSHostingView(rootView: PadView(files: files, prepareTitleFocus: { [weak self] in
            guard let self else { return }
            pendingTitleInput.discardEvents()
            makeFirstResponder(pendingTitleInput)
        }))
        NotificationCenter.default.addObserver(self, selector: #selector(applicationBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        center()
    }

    @objc private func applicationBecameActive() { requestEditorFocus() }

    func requestEditorFocus() {
        guard !editorFocusScheduled else { return }
        editorFocusScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.editorFocusScheduled = false
            guard self.isKeyWindow, self.isVisible, !self.files.settingsPresented,
                  self.firstResponder === self.pendingEditorInput || self.firstResponder === self,
                  let content = self.contentView, let editor = self.editor(in: content), editor.isEditable else { return }
            self.makeFirstResponder(editor)
        }
    }

    private func editor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, !editor.isFieldEditor { return editor }
        for child in view.subviews {
            if let editor = editor(in: child) { return editor }
        }
        return nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let action = files.editingShortcuts.action(for: event) {
            switch action {
            case .newFile: files.commandNew()
            case .open: Task { await files.openPicker() }
            case .save: files.save()
            case .saveAs: Task { await files.saveAs() }
            }
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
        if !(firstResponder is NSTextView) {
            makeFirstResponder(pendingEditorInput)
        }
        files.isActive = true
        requestEditorFocus()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        if result, let editor = responder as? NSTextView, !editor.isFieldEditor {
            // SwiftUI must finish mounting the editor and its binding before replaying input.
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, let editor, self.isKeyWindow, self.firstResponder === editor else { return }
                for event in self.pendingEditorInput.takeEvents() {
                    guard self.isKeyWindow, self.firstResponder === editor else { break }
                    self.sendEvent(event)
                }
            }
        }
        return result
    }

    override func resignKey() {
        super.resignKey()
        pendingTitleInput.discardEvents()
        pendingEditorInput.discardEvents()
        files.isActive = false
        files.lostFocus()
    }

}

private struct PadView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var files: PadDocument
    let prepareTitleFocus: () -> Void
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var renamedDocument: UUID?
    @FocusState private var editing: Bool
    @State private var shareAnchor = PadShareAnchor()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { files.close() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .frame(width: 22, height: 26)
                }
                .accessibilityLabel("Close Pad")
                if renaming {
                    HStack(spacing: 2) {
                        OverlaySearchField(placeholder: "Name", text: $titleDraft, fontSize: 14,
                                           isCurrent: { renaming && files.isActive && renamedDocument == files.documentID },
                                           submit: {
                                               guard renamedDocument == files.documentID else { return }
                                               if files.rename(to: titleDraft) { finishRename() }
                                           }, dismiss: finishRename, blur: { renaming = false })
                        Text(".\(files.url?.pathExtension ?? files.format.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 220, height: 24)
                    .background(.background, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Text(files.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .help("Double-click to rename")
                        .onTapGesture(count: 2) {
                            editing = false
                            titleDraft = files.editableName
                            renamedDocument = files.documentID
                            prepareTitleFocus()
                            renaming = true
                        }
                        .simultaneousGesture(WindowDragGesture())
                }
                DevelopmentBadge()
                if files.isDirty { Circle().frame(width: 6, height: 6).foregroundStyle(.secondary) }
                Spacer()
                HStack(spacing: 2) {
                    actionIcon("square.and.arrow.up", label: "Share", verticalOffset: -1) {
                        files.share(from: shareAnchor.view)
                    }
                    .background(PadShareAnchorView(anchor: shareAnchor).allowsHitTesting(false))

                }
                Button("Save") { files.save() }
                    .buttonStyle(PadToolbarButtonStyle(primary: true))
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 38)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { files.expand() }
                    .simultaneousGesture(WindowDragGesture())
            }

            VStack(spacing: 0) {
                TextEditor(text: $files.text)
                    .background(EditorFocusMount())
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .padding(10)
                Text(files.error ?? files.notice ?? " ")
                    .foregroundStyle(files.error == nil ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .accessibilityHidden(files.error == nil && files.notice == nil)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding([.horizontal, .bottom], 7)
        }
        // AppKit owns the outside shape, shadow and resize border as one native rounded frame.
        .glassEffect(.regular, in: .rect)
        .ignoresSafeArea()
        .disabled(files.isBusy)
        .defaultFocus($editing, true)
        .onAppear {
            let action = openSettings
            files.showSettings = { action() }
        }
        .onChange(of: files.documentID) { finishRename() }
        .onChange(of: files.isActive, initial: true) {
            if files.isActive {
                if !renaming { editing = true }
            } else {
                renaming = false
            }
        }
    }

    private func finishRename() {
        renaming = false
        editing = files.isActive
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

private struct PadToolbarButtonStyle: ButtonStyle {
    var primary = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? .primary : .secondary)
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
