import SwiftUI
import WebKit

struct PadMarkdownEditorView: NSViewRepresentable {
    let editor: PadMarkdownEditorController
    func makeNSView(context: Context) -> WKWebView { editor.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PadMarkdownToolbar: View {
    @Bindable var editor: PadMarkdownEditorController

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                formatButton("Bold", image: "bold", command: .bold)
                formatButton("Italic", image: "italic", command: .italic)
                Menu {
                    paragraphCommands
                } label: {
                    Image(systemName: "textformat.size").frame(width: 24, height: 24)
                }
                .help("Paragraph style")
                .accessibilityLabel("Paragraph style")
                formatButton("Bulleted list", image: "list.bullet", command: .bulletList)
                formatButton("Numbered list", image: "list.number", command: .orderedList)
                formatButton("Quote", image: "text.quote", command: .quote)
                Menu {
                    codeCommands
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").frame(width: 24, height: 24)
                }
                .help("Code")
                .accessibilityLabel("Code")
                Button {
                    editor.showingLink = true
                } label: {
                    Image(systemName: "link").frame(width: 24, height: 24)
                }
                .help("Link (⌘K)")
                .accessibilityLabel("Link")
            }
            .fixedSize()
            HStack(spacing: 3) {
                formatButton("Bold", image: "bold", command: .bold)
                formatButton("Italic", image: "italic", command: .italic)
                overflowMenu(includeInlineStyles: false)
            }
            .fixedSize()
            overflowMenu(includeInlineStyles: true)
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.primary)
        .tint(.primary)
        .controlSize(.small)
        .disabled(!editor.isReady)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
        .accessibilityIdentifier("markdownFormatting")
    }

    private var paragraphCommands: some View {
        Group {
            Button("Body") { editor.format(.paragraph) }
            ForEach(1...3, id: \.self) { level in
                Button("Heading \(level)") { editor.format(.heading, argument: String(level)) }
            }
        }
    }

    private var codeCommands: some View {
        Group {
            Button("Inline Code") { editor.format(.code) }
            Button("Code Block") { editor.format(.codeBlock) }
        }
    }

    private func overflowMenu(includeInlineStyles: Bool) -> some View {
        Menu {
            if includeInlineStyles {
                menuButton("Bold", image: "bold", command: .bold)
                menuButton("Italic", image: "italic", command: .italic)
                Divider()
            }
            Menu("Paragraph Style") { paragraphCommands }
            menuButton("Bulleted List", image: "list.bullet", command: .bulletList)
            menuButton("Numbered List", image: "list.number", command: .orderedList)
            menuButton("Quote", image: "text.quote", command: .quote)
            Menu("Code") { codeCommands }
            Button("Link", systemImage: "link") { editor.showingLink = true }
        } label: {
            Image(systemName: "ellipsis").frame(width: 24, height: 24)
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help("More formatting")
        .accessibilityLabel("More formatting")
        .accessibilityIdentifier("formattingOverflow")
    }

    private func menuButton(_ title: String, image: String, command: PadMarkdownFormatCommand) -> some View {
        Button(title, systemImage: image) { editor.format(command) }
            .accessibilityValue(editor.activeMarks.contains(command.rawValue) ? "On" : "Off")
            .accessibilityAddTraits(editor.activeMarks.contains(command.rawValue) ? .isSelected : [])
    }

    private func formatButton(_ title: String, image: String, command: PadMarkdownFormatCommand) -> some View {
        Button { editor.format(command) } label: {
            Image(systemName: image)
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)
                .fontWeight(editor.activeMarks.contains(command.rawValue) ? .bold : .regular)
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(editor.activeMarks.contains(command.rawValue) ? "On" : "Off")
        .accessibilityAddTraits(editor.activeMarks.contains(command.rawValue) ? .isSelected : [])
    }
}

// Keep the link anchor mounted even when the formatting controls are hidden.
struct PadMarkdownLinkPresenter: ViewModifier {
    @Bindable var editor: PadMarkdownEditorController
    @State private var linkURL = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: editor.showingLink) { _, showing in
                if showing { linkURL = "" }
            }
            .popover(isPresented: $editor.showingLink) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Link URL", text: $linkURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { insertLink() }
                    HStack {
                        if editor.activeMarks.contains("link") {
                            Button("Remove Link") {
                                editor.format(.link)
                                editor.showingLink = false
                            }
                        }
                        Spacer()
                        Button("Cancel") { editor.showingLink = false }
                        Button("Add Link") { insertLink() }
                            .disabled(validLink == nil)
                    }
                }
                .foregroundStyle(.primary)
                .tint(.primary)
                .padding(12)
                .frame(width: 300)
            }
    }

    private var validLink: String? {
        let text = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme) else { return nil }
        return text
    }

    private func insertLink() {
        guard let validLink else { return }
        editor.format(.link, argument: validLink)
        editor.showingLink = false
    }

}
