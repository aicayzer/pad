import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PadDocument.self) private var document
    @Environment(PadWorkspace.self) private var workspace
    @State private var login = LoginItemSettings()
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .pad)
    @State private var settingsWindow: NSWindow?
    @State private var showingResetConfirmation = false
    @State private var resetting = false

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Editor", systemImage: "text.alignleft") { editor }
            Tab("Files", systemImage: "doc") { files }
            Tab("Shortcuts", systemImage: "keyboard") { shortcuts }
            Tab("About", systemImage: "info.circle") { about }
        }
        // Fits the tallest settings page while keeping tab changes still.
        .frame(width: 460, height: 420)
        .tint(settings.accentColor)
        .disabled(workspace.isTransitioning)
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
                Toggle("Keep quick pad on top", isOn: $document.floating)
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
                Text("File windows appear in the Dock while they are open.")
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

    private var editor: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                windowSize(width: $settings.quickPadWidth, height: $settings.quickPadHeight,
                           identifier: "quickPadDefault")
                Button("Use Current Size") { workspace.useCurrentQuickPadSize() }
                    .accessibilityIdentifier("useCurrentQuickPadSize")
                Toggle("Snap quick pad to center", isOn: $settings.snapQuickPadToCenter)
            } header: { Text("Quick Pad") } footer: {
                Text("Resizing the window keeps this default. Choose Window → Restore Default Size to return to it.")
            }
            Section {
                windowSize(width: $settings.fileWindowWidth, height: $settings.fileWindowHeight,
                           identifier: "fileWindowDefault")
                Button("Use Current Size") { workspace.useCurrentFileSize() }
                    .disabled(!workspace.canUseFileSize)
                    .accessibilityIdentifier("useCurrentFileSize")
            } header: { Text("File Windows") } footer: {
                Text("New file windows use this size, adjusted to fit the screen.")
            }
            Section {
                Toggle("Limit text width", isOn: $settings.limitTextWidth)
                    .accessibilityIdentifier("limitTextWidth")
                LabeledContent("Column width") {
                    dimensionField(value: $settings.textColumnWidth, label: "Text column width",
                                   identifier: "textColumnWidth")
                    Text("pt").foregroundStyle(.secondary)
                }
                .disabled(!settings.limitTextWidth)
            } header: { Text("Reading") } footer: {
                Text("Centers the writing area in wider windows. Narrower windows fit the text to the available space.")
            }
        }.formStyle(.grouped)
    }

    private func windowSize(width: Binding<Double>, height: Binding<Double>, identifier: String) -> some View {
        LabeledContent("Default size") {
            dimensionField(value: width, label: "Width", identifier: identifier + "Width")
            Text("×").foregroundStyle(.secondary)
            dimensionField(value: height, label: "Height", identifier: identifier + "Height")
            Text("pt").foregroundStyle(.secondary)
        }
    }

    private func dimensionField(value: Binding<Double>, label: String, identifier: String) -> some View {
        TextField(label, value: value, format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 62)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }

    private var files: some View {
        @Bindable var settings = settings
        @Bindable var document = document
        return Form {
            Section {
                Picker("Default draft format", selection: $document.format) {
                    Text("Markdown (.md)").tag(PadFormat.md)
                    Text("Plain text (.txt)").tag(PadFormat.txt)
                }
                .tint(.primary)
                Toggle("Show format switch", isOn: $settings.showFormatToggle)
                    .accessibilityIdentifier("showFormatToggle")
            } header: { Text("Draft Format") } footer: {
                Text("Applies to the quick pad. Opened files keep their file type.")
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
            return "Saves the quick pad when you close it or switch apps. File windows save when you choose Save."
        }
        if document.reusePeriod == .alwaysNew {
            return "Temporary quick-pad drafts clear on the next opening. Saved files and their edits are kept."
        }
        return "Temporary quick-pad drafts clear after \(document.reusePeriod.title) away. Saved files and their edits are kept."
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
                Link("Website", destination: URL(string: "https://padpad.cyzr.me")!)
                Link("Source Code", destination: URL(string: "https://github.com/aicayzer/padpad")!)
                Link("Privacy Policy", destination: URL(string: "https://padpad.cyzr.me/privacy")!)
                Link("License", destination: URL(string: "https://github.com/aicayzer/padpad/blob/main/LICENSE")!)
            } footer: {
                if let error = workspace.resetError {
                    Text(error).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Reset App…") { showingResetConfirmation = true }
                        .disabled(resetting)
                        .accessibilityIdentifier("resetApp")
                        .help("Restore default settings while keeping your writing and saved files")
                }
                .padding(.top, 8)
            }
            .tint(.primary)
        }.formStyle(.grouped)
        .alert("Reset PadPad?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset App", role: .destructive) {
                resetting = true
                Task {
                    await workspace.resetApp()
                    shortcut = KeyboardShortcuts.getShortcut(for: .pad)
                    login.refresh()
                    resetting = false
                }
            }
        } message: {
            Text("Your settings will return to their defaults. Your writing and saved files will be kept.")
        }
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
            Section("Window") {
                LabeledContent("Restore Default Size", value: document.editingShortcuts.restoreSizeShortcutAvailable
                               ? "⌘0" : "Use the Window menu")
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
