import AppKit

struct PadClipboardContents: Equatable {
    let text: String
    var html: String?

    @MainActor
    func write(to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let html { item.setString(html, forType: .html) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
