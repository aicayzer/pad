import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    #if DEBUG
    static let pad = Self("pad", default: .init(.p, modifiers: [.control, .option, .command, .shift]))
    #else
    static let pad = Self("pad", default: .init(.b, modifiers: [.option, .shift]))
    #endif
}
