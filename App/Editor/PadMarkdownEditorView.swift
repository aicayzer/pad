import AppKit
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
            HStack(spacing: 4) {
                headingMenu
                styleMenu
                linkButton
                formatButton("Inline code", image: "chevron.left.forwardslash.chevron.right", command: .code)
                formatButton("Code block", image: "curlybraces", command: .codeBlock, size: 13.5)
                formatButton("Quote", image: "text.quote", command: .quote, size: 13.5)
                listMenu
            }
            .fixedSize()
            overflowMenu
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .disabled(!editor.isReady)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown formatting")
        .accessibilityIdentifier("markdownFormatting")
    }

    private var headingMenu: some View {
        Menu { headingCommands } label: {
            PadFormattingMenuLabel(selected: active(.heading)) {
                PadFormattingGlyph(text: "H", design: .rounded, selected: active(.heading))
            }
        }
        .tint(active(.heading) ? .primary : .secondary)
        .help("Headings")
        .accessibilityLabel("Headings")
        .accessibilityIdentifier("headingFormatting")
        .accessibilityValue(active(.heading) ? "On" : "Off")
    }

    private var styleMenu: some View {
        Menu { styleCommands } label: {
            PadFormattingMenuLabel(selected: active(.bold) || active(.italic)) {
                PadFormattingGlyph(text: "I", design: .serif, selected: active(.bold) || active(.italic))
            }
        }
        .tint(active(.bold) || active(.italic) ? .primary : .secondary)
        .help("Text style")
        .accessibilityLabel("Text style")
        .accessibilityValue(active(.bold) || active(.italic) ? "On" : "Off")
    }

    private var listMenu: some View {
        Menu { listCommands } label: {
            PadFormattingMenuLabel(selected: active(.bulletList) || active(.orderedList)) {
                PadFormattingGlyph(symbol: active(.orderedList) ? "list.number" : "list.bullet",
                                   selected: active(.bulletList) || active(.orderedList))
            }
        }
        .tint(active(.bulletList) || active(.orderedList) ? .primary : .secondary)
        .help("Lists")
        .accessibilityLabel("Lists")
        .accessibilityValue(active(.bulletList) || active(.orderedList) ? "On" : "Off")
    }

    private var headingCommands: some View {
        Group {
            Toggle("Body", isOn: Binding(get: { !active(.heading) }, set: { _ in editor.format(.paragraph) }))
            ForEach(1...3, id: \.self) { level in
                Toggle("Heading \(level)", isOn: Binding(
                    get: { editor.activeMarks.contains("heading\(level)") },
                    set: { _ in editor.format(.heading, argument: String(level)) }
                ))
            }
        }
    }

    private var styleCommands: some View {
        Group {
            formatToggle("Bold", command: .bold)
            formatToggle("Italic", command: .italic)
        }
    }

    private var listCommands: some View {
        Group {
            formatToggle("Bulleted list", command: .bulletList)
            formatToggle("Numbered list", command: .orderedList)
        }
    }

    private var linkButton: some View {
        Button { editor.showingLink = true } label: {
            PadFormattingGlyph(symbol: "link", selected: active(.link), size: 13.5)
        }
        .buttonStyle(PadFormattingButtonStyle())
        .help("Link (⌘K)")
        .accessibilityLabel("Link")
        .accessibilityValue(active(.link) ? "On" : "Off")
        .accessibilityAddTraits(active(.link) ? .isSelected : [])
    }

    private var overflowMenu: some View {
        Menu {
            Menu("Headings") { headingCommands }
            Menu("Text style") { styleCommands }
            Divider()
            Button("Link") { editor.showingLink = true }
            formatToggle("Inline code", command: .code)
            formatToggle("Code block", command: .codeBlock)
            formatToggle("Quote", command: .quote)
            Divider()
            Menu("Lists") { listCommands }
        } label: {
            PadFormattingMenuLabel {
                PadFormattingGlyph(symbol: "ellipsis")
            }
        }
        .fixedSize()
        .tint(.secondary)
        .help("More formatting")
        .accessibilityLabel("More formatting")
        .accessibilityIdentifier("formattingOverflow")
    }

    private func active(_ command: PadMarkdownFormatCommand) -> Bool {
        editor.activeMarks.contains(command.rawValue)
    }

    private func formatToggle(_ title: String, command: PadMarkdownFormatCommand) -> some View {
        Toggle(title, isOn: Binding(get: { active(command) }, set: { _ in editor.format(command) }))
    }

    private func formatButton(_ title: String, image: String, command: PadMarkdownFormatCommand, size: CGFloat = 14) -> some View {
        Button { editor.format(command) } label: {
            PadFormattingGlyph(symbol: image, selected: active(command), size: size)
        }
        .buttonStyle(PadFormattingButtonStyle())
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(active(command) ? "On" : "Off")
        .accessibilityAddTraits(active(command) ? .isSelected : [])
    }
}

// Flatten every glyph into the same monochrome image so native menus and
// ordinary buttons cannot apply different symbol palettes or accent colors.
private struct PadFormattingGlyph: View {
    var symbol: String?
    var text: String?
    var design: NSFontDescriptor.SystemDesign = .default
    var selected = false
    var size: CGFloat = 14

    var body: some View {
        Image(nsImage: image).renderingMode(.original).frame(width: 22, height: 22)
    }

    private var image: NSImage {
        let canvas = NSSize(width: 22, height: 22)
        let image = NSImage(size: canvas, flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = NSColor(calibratedWhite: selected ? (dark ? 0.9 : 0.28) : 0.6, alpha: 1)
            if let text {
                let fontSize: CGFloat = 18
                let base = NSFont.systemFont(ofSize: fontSize, weight: text == "H" ? .semibold : .medium)
                let font = base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
                let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                let extent = string.size()
                // Align the visible capital, rather than its line-height box.
                string.draw(at: NSPoint(x: (rect.width - extent.width) / 2,
                                        y: (rect.height - font.capHeight) / 2 + font.descender))
            } else {
                let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
                guard let source = NSImage(systemSymbolName: symbol ?? "ellipsis", accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration) else { return false }
                let raster = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                raster.size = canvas
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: raster)
                source.draw(in: NSRect(x: (22 - source.size.width) / 2, y: (22 - source.size.height) / 2,
                                       width: source.size.width, height: source.size.height))
                NSGraphicsContext.current?.compositingOperation = .sourceIn
                color.setFill()
                NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
                NSGraphicsContext.restoreGraphicsState()
                raster.draw(in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct PadFormattingMenuLabel<Content: View>: View {
    var selected = false
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        content()
        .frame(width: 26, height: 28)
        .background(Color.primary.opacity(hovered ? 0.08 : 0), in: Capsule())
        .contentShape(Capsule())
        .onHover { hovered = $0 }
    }
}

struct PadFormattingButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 28)
            .background(Color.primary.opacity(hovered || configuration.isPressed ? 0.08 : 0), in: Capsule())
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
