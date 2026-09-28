import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let isTestHost = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }
    let settings: AppSettings
    let document: PadDocument
    private var receivedFile = false

    override init() {
        let defaults = Self.isTestHost ? UserDefaults(suiteName: "tests-\(UUID().uuidString)")! : .standard
        settings = AppSettings(defaults: defaults)
        document = PadDocument(defaults: defaults, presentsWindow: !Self.isTestHost)
        super.init()
        if Self.isTestHost { KeyboardShortcuts.isEnabled = false }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        settings.applyActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        document.installShortcut()
        if !receivedFile, !LoginItemSettings.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent) {
            document.newFile()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !Self.isTestHost else { return }
        for url in urls where url.isFileURL { receivedFile = true; document.open(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !Self.isTestHost else { return false }
        document.showCurrent()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard !Self.isTestHost else { return }
        settings.applyActivationPolicy()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        document.canTerminate() ? .terminateNow : .terminateCancel
    }
}
