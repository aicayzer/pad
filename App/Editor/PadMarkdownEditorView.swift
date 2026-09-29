import SwiftUI
import WebKit

struct PadMarkdownEditorView: NSViewRepresentable {
    let editor: PadMarkdownEditorController
    func makeNSView(context: Context) -> WKWebView { editor.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PadMarkdownToolbar: View {
    @Bindable var editor: PadMarkdownEditorController
    @State private var linkURL = ""

    var body: some View {
        HStack(spacing: 3) {
            formatButton("Bold", image: "bold", command: .bold)
            formatButton("Italic", image: "italic", command: .italic)
            Menu {
                Button("Body") { editor.format(.paragraph) }
                ForEach(1...3, id: \.self) { level in
                    Button("Heading \(level)") { editor.format(.heading, argument: String(level)) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Paragraph style")
            .accessibilityLabel("Paragraph style")
            formatButton("Bulleted list", image: "list.bullet", command: .bulletList)
            formatButton("Numbered list", image: "list.number", command: .orderedList)
            formatButton("Quote", image: "text.quote", command: .quote)
            Menu {
                Button("Inline Code") { editor.format(.code) }
                Button("Code Block") { editor.format(.codeBlock) }
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Code")
            .accessibilityLabel("Code")
            Button {
                linkURL = ""
                editor.showingLink = true
            } label: {
                Image(systemName: "link").frame(width: 24, height: 24)
            }
            .keyboardShortcut("k", modifiers: .command)
            .help("Link (⌘K)")
            .accessibilityLabel("Link")
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
                .padding(12)
                .frame(width: 300)
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!editor.isReady)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
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

    private func formatButton(_ title: String, image: String, command: PadMarkdownFormatCommand) -> some View {
        Button { editor.format(command) } label: {
            Image(systemName: image)
                .frame(width: 24, height: 24)
                .foregroundStyle(editor.activeMarks.contains(command.rawValue) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(editor.activeMarks.contains(command.rawValue) ? .isSelected : [])
    }
}
