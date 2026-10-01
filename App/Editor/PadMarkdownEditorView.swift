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
                headingMenu
                formatButton("Bold", image: "bold", command: .bold)
                formatButton("Italic", image: "italic", command: .italic)
                formatButton("Bulleted list", image: "list.bullet", command: .bulletList)
                formatButton("Numbered list", image: "list.number", command: .orderedList)
                formatButton("Quote", image: "text.quote", command: .quote)
                Menu { codeCommands } label: {
                    PadFormattingMenuLabel(selected: !editor.activeMarks.isDisjoint(with: ["code", "codeBlock"])) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .help("Code")
                .accessibilityLabel("Code")
                Button { editor.showingLink = true } label: {
                    Image(systemName: "link").frame(width: 16, height: 16)
                }
                .buttonStyle(PadFormattingButtonStyle(selected: editor.activeMarks.contains("link")))
                .help("Link (⌘K)")
                .accessibilityLabel("Link")
            }
            .fixedSize()
            HStack(spacing: 3) {
                headingMenu
                formatButton("Bold", image: "bold", command: .bold)
                formatButton("Italic", image: "italic", command: .italic)
                overflowMenu(includeInlineStyles: false, includeHeadings: false)
            }
            .fixedSize()
            overflowMenu(includeInlineStyles: true, includeHeadings: true)
        }
        .buttonStyle(PadFormattingButtonStyle())
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .tint(.primary)
        .controlSize(.small)
        .disabled(!editor.isReady)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
        .accessibilityIdentifier("markdownFormatting")
    }

    private var headingMenu: some View {
        Menu { headingCommands } label: {
            PadFormattingMenuLabel(selected: editor.activeMarks.contains("heading")) { Text("H") }
        }
        .help("Headings")
        .accessibilityLabel("Headings")
        .accessibilityIdentifier("headingFormatting")
        .accessibilityValue(editor.activeMarks.contains("heading") ? "On" : "Off")
    }

    private var headingCommands: some View {
        ForEach(1...3, id: \.self) { level in
            Toggle("Heading \(level)", isOn: Binding(
                get: { editor.activeMarks.contains("heading\(level)") },
                set: { _ in editor.format(.heading, argument: String(level)) }
            ))
        }
    }

    private var codeCommands: some View {
        Group {
            Button("Inline Code") { editor.format(.code) }
            Button("Code Block") { editor.format(.codeBlock) }
        }
    }

    private func overflowMenu(includeInlineStyles: Bool, includeHeadings: Bool) -> some View {
        Menu {
            if includeHeadings { Menu("Headings") { headingCommands } }
            if includeInlineStyles {
                menuButton("Bold", image: "bold", command: .bold)
                menuButton("Italic", image: "italic", command: .italic)
                Divider()
            }
            menuButton("Bulleted List", image: "list.bullet", command: .bulletList)
            menuButton("Numbered List", image: "list.number", command: .orderedList)
            menuButton("Quote", image: "text.quote", command: .quote)
            Menu("Code") { codeCommands }
            Button("Link", systemImage: "link") { editor.showingLink = true }
        } label: {
            PadFormattingMenuLabel { Image(systemName: "ellipsis") }
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
            Image(systemName: image).frame(width: 16, height: 16)
        }
        .buttonStyle(PadFormattingButtonStyle(selected: editor.activeMarks.contains(command.rawValue)))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(editor.activeMarks.contains(command.rawValue) ? "On" : "Off")
        .accessibilityAddTraits(editor.activeMarks.contains(command.rawValue) ? .isSelected : [])
    }
}

// Native Menu buttons do not use a custom ButtonStyle. Paint the same hover treatment in their label.
private struct PadFormattingMenuLabel<Content: View>: View {
    var selected = false
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        content()
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(width: 16, height: 16)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hovered ? 0.1 : 0), in: Capsule())
            .contentShape(Capsule())
            .onHover { hovered = $0 }
    }
}

struct PadFormattingButtonStyle: ButtonStyle {
    var selected = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hovered || configuration.isPressed ? 0.1 : 0), in: Capsule())
            .contentShape(Capsule())
            .onHover { hovered = $0 }
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
