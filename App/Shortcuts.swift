import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    #if DEBUG
    static let pad = Self("pad", default: .init(.b, modifiers: [.control, .shift]))
    #else
    static let pad = Self("pad", default: .init(.b, modifiers: [.option, .shift]))
    #endif
}
