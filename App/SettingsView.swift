import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PadDocument.self) private var document
    @State private var login = LoginItemSettings()
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .pad)
    @State private var settingsWindow: NSWindow?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Files", systemImage: "doc") { files }
            Tab("Shortcuts", systemImage: "keyboard") { shortcuts }
        }
        .frame(width: 460, height: 580)
        .tint(settings.accentColor)
        .background(WindowReader { window in
            settingsWindow = window
            #if DEBUG
            window.level = .normal
            #else
            window.level = .floating
            #endif
            document.settingsPresented = true
        })
        .onAppear {
            document.settingsPresented = true
            document.isActive = false
            NSApp.activate()
            login.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if notification.object as? NSWindow === settingsWindow { releaseSettingsFocus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if notification.object as? NSWindow === settingsWindow {
                document.settingsPresented = true
                document.isActive = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard notification.object as? NSWindow === settingsWindow else { return }
            DispatchQueue.main.async {
                // A color or file panel is still part of Settings, not dismissal to another app.
                if !NSApp.isActive || document.isActive { releaseSettingsFocus() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if document.settingsPresented { releaseSettingsFocus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }

    private func releaseSettingsFocus() {
        document.settingsPresented = false
        if !document.isActive { document.lostFocus() }
    }

    private var general: some View {
        @Bindable var settings = settings
        @Bindable var document = document
        return Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { enabled in Task { await login.setEnabled(enabled) } }))
                    .disabled(login.updating)
                if login.status == .requiresApproval { Button("Allow in Login Items…") { login.openSystemSettings() } }
                if let error = login.error { Text(error).foregroundStyle(.red) }
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .disabled(settings.showInDock && !settings.menuBarItem && shortcut == nil)
                Toggle("Show in menu bar", isOn: $settings.menuBarItem)
                    .disabled(settings.menuBarItem && !settings.showInDock && shortcut == nil)
            } header: { Text("App") } footer: {
                if settings.policyPending { Text("Dock change applies when you leave Pad.") }
                if !settings.showInDock && !settings.menuBarItem, let shortcut {
                    Text("Open Pad with \(shortcut.description).")
                }
            }
            Section("Appearance") {
                Picker("Accent", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { Text($0.title).tag($0) }
                }
                if settings.accent == .custom {
                    ColorPicker("Accent color", selection: Binding(get: { settings.accentColor }, set: { settings.setCustomAccent($0) }), supportsOpacity: false)
                }
                LabeledContent("Menu bar icon") {
                    Menu {
                        ForEach(MenuBarIcon.allCases) { icon in
                            Button { settings.menuBarIcon = icon } label: {
                                icon.image.accessibilityLabel(icon.title)
                            }
                        }
                    } label: {
                        settings.menuBarIcon.image
                    }
                    .menuStyle(.button)
                    .menuIndicator(.visible)
                    .buttonStyle(.borderless)
                    .tint(.primary)
                    .fixedSize()
                    .accessibilityLabel("Menu bar icon")
                    .accessibilityValue(settings.menuBarIcon.title)
                }
                .disabled(!settings.menuBarItem)
                Toggle("Always on top", isOn: $document.floating)
            }
            Section("About") {
                LabeledContent("Version", value: "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                Link(destination: URL(string: "https://github.com/aicayzer/pad")!) {
                    Text("Source Code").foregroundStyle(settings.accentColor)
                }
                Link(destination: URL(string: "https://github.com/aicayzer/pad/releases")!) {
                    Text("Releases").foregroundStyle(settings.accentColor)
                }
                Link(destination: URL(string: "https://github.com/aicayzer/pad/blob/main/LICENSE")!) {
                    Text("License").foregroundStyle(settings.accentColor)
                }
            }
        }.formStyle(.grouped)
    }

    private var files: some View {
        @Bindable var document = document
        return Form {
            Section {
                Toggle("Save when Pad closes", isOn: $document.saveAutomatically)
                LabeledContent("Save to") {
                    Text(document.folder.lastPathComponent).foregroundStyle(.secondary).lineLimit(1).help(document.folder.path)
                    Button("Choose…") { Task { await document.chooseFolder() } }
                }
                if !document.isDefaultFolder { Button("Use Downloads") { document.useDownloads() } }
                Picker("Default format", selection: $document.format) {
                    Text("Plain text (.txt)").tag(PadFormat.txt)
                    Text("Markdown (.md)").tag(PadFormat.md)
                }
            } header: { Text("Saving") } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Includes closing Pad by switching to another app.")
                    if !document.saveAutomatically {
                        Text("Unsaved scratch text is discarded when Pad closes. Existing files ask before discarding changes.")
                    }
                    if let error = document.error { Text(error).foregroundStyle(.red) }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Default filename").fixedSize()
                        Spacer(minLength: 0)
                        Text("Example: \(document.namePreview)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(document.namePreview)
                    }
                    PadNameField(parts: $document.nameParts).frame(height: 26)
                }
            } header: { Text("Naming") } footer: {
                Text("Add date or number variables with +. Rename an individual file in its title.")
            }
            Section {
                Picker("Reuse current scratch file", selection: $document.reusePeriod) {
                    ForEach(PadReuse.allCases) { Text($0.title).tag($0) }
                }
            } header: { Text("Reopening") } footer: {
                Text("Reopen the same scratch file within this interval. New Text File always starts a fresh file. Opened files stay open until you choose another file.")
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Global Shortcut") {
                KeyboardShortcuts.Recorder("Show or hide Pad", name: .pad) { value in
                    shortcut = value
                    // Keep an entry point when the final global shortcut is removed.
                    if value == nil && !settings.showInDock && !settings.menuBarItem { settings.menuBarItem = true }
                }
                .shortcutValidation { document.editingShortcuts.validateGlobal($0) }
            }
            Section("While Editing") {
                EditingShortcutSettings(shortcuts: document.editingShortcuts)
            }
        }.formStyle(.grouped)
    }
}
