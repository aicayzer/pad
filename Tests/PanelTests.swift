import AppKit
import KeyboardShortcuts
import SwiftUI
import Testing
@testable import Pad

@MainActor
@Suite(.serialized, .opensWindows)
struct PanelTests {
    // Run this suite separately from other window suites: AppKit has one key window per process.
    @Test func editorFocusSettingsAndDocumentLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pad-panel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "pad-panel-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let document = PadDocument(defaults: defaults, defaultFolder: root,
                                   noticeDuration: .milliseconds(150), copyPath: { _ in })
        let initialWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let trace = PanelActivationTrace()
        defer { trace.stop() }
        NSApp.activate()
        document.newFile()
        let panel = try #require(NSApp.windows.compactMap { $0 as? PadPanel }.first {
            !initialWindows.contains(ObjectIdentifier($0))
        })
        let settingsWindow = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 460, height: 580),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settingsWindow.isReleasedWhenClosed = false
        defer {
            document.showSettings = {}
            document.settingsPresented = false
            document.saveAutomatically = false
            document.text = document.savedText
            settingsWindow.orderOut(nil)
            settingsWindow.contentView = nil
            settingsWindow.close()
            document.close()
            panel.contentView = nil
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        // Real key events arrive one character at a time, including before SwiftUI mounts.
        for (character, keyCode) in [("f", UInt16(3)), ("a", 0), ("s", 1), ("t", 17), (" ", 49)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                    characters: character, charactersIgnoringModifiers: character,
                                                    isARepeat: false, keyCode: keyCode))
            panel.sendEvent(event)
        }
        let queuedAfterInput = panel.pendingEditorEventCount
        try await eventually("initial editor focus") { panel.isKeyWindow && panel.firstResponder is NSTextView }
        let editor = try #require(panel.firstResponder as? NSTextView)
        #expect(document.isActive)
        try await eventually("keystrokes before editor mount", diagnostics: {
            "document=\(String(reflecting: document.text)) editor=\(String(reflecting: editor.string)) queuedAfterInput=\(queuedAfterInput) queuedNow=\(panel.pendingEditorEventCount)"
        }) { document.text == "fast " }
        editor.insertText("A small place to write.\n\nThis is a disposable test document.", replacementRange: editor.selectedRange())
        try await eventually("initial text binding") { document.text == editor.string && !document.text.isEmpty }
        let originalText = document.text
        let originalID = document.documentID

        // A scratch document must survive opening Settings even when automatic saving is off.
        document.saveAutomatically = false
        let settings = AppSettings(defaults: defaults)
        settingsWindow.contentView = NSHostingView(rootView: SettingsView().environment(settings).environment(document))
        document.showSettings = {
            settingsWindow.makeKeyAndOrderFront(nil)
        }
        #expect(try command(.comma, character: ",", in: panel))
        try await eventually("settings focus and guard", diagnostics: { trace.events.joined(separator: "\n") }) {
            settingsWindow.isKeyWindow && document.settingsPresented
        }
        #expect(panel.isVisible)
        #expect(document.text == originalText)
        #expect(document.documentID == originalID)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            settingsWindow.appearance = NSAppearance(named: appearance)
            try await settle()
            try capture(settingsWindow, name: "settings-\(name)")
        }
        // Opening an already-visible Pad must preserve its file even outside the reuse interval.
        document.showCurrent(now: .now.addingTimeInterval(24 * 60 * 60))
        try await eventually("return from settings") { panel.isKeyWindow && document.isActive && !document.settingsPresented }
        #expect(document.text == originalText)
        #expect(document.documentID == originalID)
        try await eventually("editor focus after settings") { panel.firstResponder is NSTextView }
        let returnedEditor = try #require(panel.firstResponder as? NSTextView)
        returnedEditor.insertText("\nStill here after Settings.", replacementRange: NSRange(location: returnedEditor.string.utf16.count, length: 0))
        try await eventually("text input after settings") { document.text.hasSuffix("Still here after Settings.") }

        document.saveAutomatically = true
        document.save()
        #expect(document.notice != nil)
        let scrollView = try #require(returnedEditor.enclosingScrollView)
        panel.contentView?.layoutSubtreeIfNeeded()
        let noticeFrame = scrollView.frame
        try await eventually("notice expiration") { document.notice == nil }
        try await settle()
        panel.contentView?.layoutSubtreeIfNeeded()
        #expect(scrollView.frame == noticeFrame)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            panel.appearance = NSAppearance(named: appearance)
            try await settle()
            try capture(panel, name: "editor-\(name)")
        }

        let savedURL = try #require(document.url)
        #expect(try command(.n, character: "n", in: panel))
        #expect(document.documentID != originalID)
        #expect(document.text.isEmpty)
        #expect(document.url == nil)
        #expect(try String(contentsOf: savedURL, encoding: .utf8).contains("Still here after Settings."))
        document.text = "Reuse this scratch file."
        let reusableID = document.documentID
        document.close()
        #expect(!panel.isVisible)
        let reusableURL = try #require(document.url)
        document.toggle()
        try await eventually("reopen panel focus") { panel.isVisible && panel.isKeyWindow }
        #expect(document.documentID == reusableID)
        #expect(document.url == reusableURL)
        #expect(document.text == "Reuse this scratch file.")
    }

    @Test func failedCloseKeepsWindowAndDraftUntilSaveSucceeds() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "pad-close-\(UUID().uuidString)")
        let suite = "pad-close-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let document = PadDocument(defaults: defaults, defaultFolder: root, copyPath: { _ in })
        defer {
            document.saveAutomatically = false
            document.text = document.savedText
            document.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        document.newFile()
        document.text = "Preserve this draft when its save folder is missing."
        document.close()
        #expect(document.isVisible)
        #expect(document.isDirty)
        #expect(document.error != nil)
        #expect(!document.isBusy)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        document.close()
        #expect(!document.isVisible)
        #expect(!document.isDirty)
        let saved = try #require(document.url)
        #expect(try String(contentsOf: saved, encoding: .utf8) == document.text)
    }

    private func command(_ key: KeyboardShortcuts.Key, character: String, in panel: PadPanel) throws -> Bool {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                characters: character, charactersIgnoringModifiers: character,
                                                isARepeat: false, keyCode: UInt16(key.rawValue)))
        return panel.performKeyEquivalent(with: event)
    }

    private func eventually(_ step: String, diagnostics: @MainActor () -> String = { "" },
                            sourceLocation: SourceLocation = #_sourceLocation,
                            _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let windows = NSApp.windows.map { window in
            let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            return "\(type(of: window)) #\(window.windowNumber) key=\(window.isKeyWindow) visible=\(window.isVisible) activeSpace=\(window.isOnActiveSpace) occlusion=\(window.occlusionState.rawValue) firstResponder=\(responder)"
        }.joined(separator: "\n")
        let key = NSApp.keyWindow.map { String($0.windowNumber) } ?? "nil"
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        let diagnostic = "Step: \(step). appActive=\(NSApp.isActive) appKeyWindow=\(key) foreground=\(frontmost)\n\(diagnostics())\n\(windows)"
        try #require(condition(), Comment(rawValue: diagnostic), sourceLocation: sourceLocation)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["PAD_QA_OUTPUT"] else { return }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: folder.appending(path: "\(name).png"), options: .atomic)
    }
}

@MainActor
private final class PanelActivationTrace: NSObject {
    private(set) var events: [String] = []

    override init() {
        super.init()
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(record(_:)), name: name, object: nil)
        }
    }

    func stop() { NotificationCenter.default.removeObserver(self) }

    @objc private func record(_ notification: Notification) {
        let source = (notification.object as? NSWindow).map { "\(type(of: $0)) #\($0.windowNumber)" } ?? "application"
        let key = NSApp.keyWindow.map { String($0.windowNumber) } ?? "nil"
        events.append("\(notification.name.rawValue): \(source), appActive=\(NSApp.isActive), keyWindow=\(key)")
    }
}
