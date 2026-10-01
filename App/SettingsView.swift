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
            Tab("About", systemImage: "info.circle") { about }
        }
        // Fits the tallest settings page while keeping tab changes still.
        .frame(width: 460, height: 420)
        .tint(settings.accentColor)
        .background(WindowReader { window in
            settingsWindow = window
            window.level = document.floating ? .floating : .normal
            document.settingsPresented = true
        })
        .onChange(of: document.floating) { _, floating in
            settingsWindow?.level = floating ? .floating : .normal
        }
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
            guard notification.object as? NSWindow === settingsWindow,
                  !settings.isChangingActivationPolicy else { return }
            DispatchQueue.main.async {
                guard !settings.isChangingActivationPolicy else { return }
                // A color or file panel is still part of Settings, not dismissal to another app.
                if !NSApp.isActive || document.isActive { releaseSettingsFocus() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if document.settingsPresented, !settings.isChangingActivationPolicy { releaseSettingsFocus() }
        }
        .onChange(of: settings.isChangingActivationPolicy) { _, changing in
            guard !changing else { return }
            if settingsWindow?.isKeyWindow == true {
                document.settingsPresented = true
                document.isActive = false
            } else if !NSApp.isActive, document.settingsPresented {
                releaseSettingsFocus()
            }
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
                Toggle("Always on top", isOn: $document.floating)
                Picker("App access", selection: Binding(
                    get: { settings.access },
                    set: { settings.setAccess($0, hasGlobalShortcut: shortcut != nil, from: settingsWindow) }
                )) {
                    ForEach(AppAccess.visibleChoices) { Text($0.title).tag($0) }
                    if settings.access == .shortcutOnly {
                        Text(AppAccess.shortcutOnly.title).tag(AppAccess.shortcutOnly)
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("appAccess")
            } header: { Text("App") } footer: {
                if let error = settings.activationPolicyError { Text(error).foregroundStyle(.red) }
                if !settings.showInDock && !settings.menuBarItem, let shortcut {
                    Text("Open \(Bundle.main.displayName) with \(shortcut.description).")
                }
            }
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
                }
                .tint(.primary)
                .accessibilityIdentifier("appearance")
                Picker("Accent", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { Text($0.title).tag($0) }
                }
                .tint(.primary)
                if settings.accent == .custom {
                    ColorPicker("Accent color", selection: Binding(get: { settings.accentColor }, set: { settings.setCustomAccent($0) }), supportsOpacity: false)
                }
                LabeledContent("Menu bar icon") {
                    MenuBarIconPicker(selection: $settings.menuBarIcon)
                        .fixedSize()
                        .accessibilityLabel("Menu bar icon")
                }
                .disabled(!settings.menuBarItem)
            }
        }.formStyle(.grouped)
    }

    private var files: some View {
        @Bindable var settings = settings
        @Bindable var document = document
        return Form {
            Section("Format") {
                Picker("Default format", selection: $document.format) {
                    Text("Markdown (.md)").tag(PadFormat.md)
                    Text("Plain text (.txt)").tag(PadFormat.txt)
                }
                .tint(.primary)
                Toggle("Show format switch", isOn: $settings.showFormatToggle)
                    .accessibilityIdentifier("showFormatToggle")
            }
            Section {
                Toggle("Save automatically", isOn: $document.saveAutomatically)
                Picker("Draft lifetime", selection: $document.reusePeriod) {
                    ForEach(PadReuse.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("draftLifetime")
            } header: { Text("Draft") } footer: {
                Text(draftExplanation)
            }
            Section {
                LabeledContent("Save location") {
                    Text(document.folder.lastPathComponent).foregroundStyle(.secondary).lineLimit(1).help(document.folder.path)
                    Button("Choose…") { Task { await document.chooseFolder(parent: settingsWindow) } }
                        .tint(.primary)
                }
                if !document.isDefaultFolder {
                    Button("Use Downloads") { document.useDownloads() }
                        .tint(.primary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Filename").fixedSize()
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
            } header: { Text("Files") } footer: {
                if let error = document.error { Text(error).foregroundStyle(.red) }
            }
        }.formStyle(.grouped)
    }

    private var draftExplanation: String {
        if document.saveAutomatically {
            return "Saves to a file when you close the pad or switch apps."
        }
        if document.reusePeriod == .alwaysNew {
            return "Unsaved drafts clear on the next opening."
        }
        return "Unsaved drafts clear after \(document.reusePeriod.title) away."
    }

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    LabeledContent(Bundle.main.displayName, value: "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                }
                Text("A place for text and Markdown.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Link("Source Code", destination: URL(string: "https://github.com/aicayzer/pad")!)
                Link("Releases", destination: URL(string: "https://github.com/aicayzer/pad/releases")!)
                Link("License", destination: URL(string: "https://github.com/aicayzer/pad/blob/main/LICENSE")!)
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset onboarding") {
                        Task {
                            await document.restartOnboarding()
                            if document.onboarding.isPresented { settingsWindow?.orderOut(nil) }
                        }
                    }
                    .accessibilityIdentifier("resetOnboarding")
                    .help("Replay the introduction without changing your settings or document")
                }
                .padding(.top, 8)
            }
            .tint(.primary)
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Global Shortcut") {
                KeyboardShortcuts.Recorder("Show or hide \(Bundle.main.displayName)", name: .pad) { value in
                    shortcut = value
                    // Keep an entry point when the final global shortcut is removed.
                    if value == nil && !settings.showInDock && !settings.menuBarItem { settings.menuBarItem = true }
                }
                .shortcutValidation { document.editingShortcuts.validateGlobal($0) }
            }
            Section {
                EditingShortcutSettings(shortcuts: document.editingShortcuts)
            } header: {
                Text("While Editing")
            } footer: {
                VStack(alignment: .trailing, spacing: 8) {
                    if let error = document.editingShortcuts.error {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                    HStack {
                        if document.editingShortcuts.copyAllShortcutAvailable {
                            Text("Copy All Contents: ⇧⌘C").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore Defaults") { document.editingShortcuts.restoreDefaults() }
                            .tint(.primary)
                            .disabled(document.editingShortcuts.isDefault)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.formStyle(.grouped)
    }
}
