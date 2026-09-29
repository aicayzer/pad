import SwiftUI

@main
struct PadApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings {
            SettingsView().environment(delegate.settings).environment(delegate.document)
                .preferredColorScheme(delegate.settings.appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .commands { AppCommands(document: delegate.document) }

        MenuBarExtra(isInserted: Binding(get: { !AppDelegate.isTestHost && delegate.settings.menuBarItem }, set: { delegate.settings.menuBarItem = $0 })) {
            Button("Open \(Bundle.main.displayName)") { delegate.document.showCurrent() }
            Button("New Text File") { delegate.document.commandNew() }
            Button("Open File…") { Task { await delegate.document.openPicker() } }
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit \(Bundle.main.displayName)") { NSApp.terminate(nil) }
        } label: {
            delegate.settings.menuBarIcon.image.accessibilityLabel(Bundle.main.displayName)
        }
    }
}

extension Bundle {
    var displayName: String { object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "" }
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
}
