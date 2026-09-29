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
                editor.showingLink = true
            } label: {
                Image(systemName: "link").frame(width: 24, height: 24)
            }
            .help("Link (⌘K)")
            .accessibilityLabel("Link")
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .tint(.primary)
        .controlSize(.small)
        .disabled(!editor.isReady)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
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

// Keep the link anchor mounted even when the formatting row is hidden.
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
