import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let isTestHost = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }
    let settings: AppSettings
    let document: PadDocument

    override init() {
        let defaults = Self.isTestHost ? UserDefaults(suiteName: "tests-\(UUID().uuidString)")! : .standard
        settings = AppSettings(defaults: defaults)
        document = PadDocument(defaults: defaults, presentsWindow: !Self.isTestHost)
        super.init()
        document.appSettings = settings
        if Self.isTestHost { KeyboardShortcuts.isEnabled = false }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        settings.applyAppearance()
        settings.applyActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        document.installShortcut()
        // SwiftUI finishes creating its scenes after the delegate's early launch callback.
        // Reapply the saved access policy once scene setup has settled, without opening a draft.
        DispatchQueue.main.async { [weak self] in self?.settings.applyActivationPolicy() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        settings.applyActivationPolicy()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !Self.isTestHost else { return }
        for url in urls where url.isFileURL { document.open(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !Self.isTestHost else { return false }
        document.showCurrent()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if document.editorSnapshot != nil {
            Task { sender.reply(toApplicationShouldTerminate: await document.prepareToTerminate()) }
            return .terminateLater
        }
        return document.canTerminate() ? .terminateNow : .terminateCancel
    }
}
