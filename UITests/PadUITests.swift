import AppKit
import XCTest

@MainActor
final class PadUITests: XCTestCase {
    func testSettingsPreservesScratchAndEditorAcceptsInput() throws {
        let app = launchPad()
        defer { app.terminate() }

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        attach(app.screenshot(), name: "Pad editor before input")
        var original = "Disposable Pad UI test \(UUID().uuidString)"
        // Do not click the editor first: launch must establish its keyboard focus.
        app.typeText(original)
        expectValue(original, in: editor)
        attach(app.screenshot(), name: "Pad editor after launch")

        app.staticTexts["Untitled"].firstMatch.doubleClick()
        app.typeText("UI Test Draft")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["UI Test Draft.txt"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.typeKey(.downArrow, modifierFlags: .command)
        let afterRename = "\nTyping after rename."
        app.typeText(afterRename)
        original += afterRename
        expectValue(original, in: editor)
        attach(app.screenshot(), name: "Pad title rename and continued input")

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        selectTab("General", in: settings)
        let login = settings.staticTexts["Open at login"].firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(login.isHittable, app.debugDescription)
        expectValue(original, in: editor)
        attach(settings.screenshot(), name: "Pad Settings General")

        selectTab("Files", in: settings)
        XCTAssertTrue(settings.staticTexts["Save when Pad closes"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        expectValue(original, in: editor)
        attach(settings.screenshot(), name: "Pad Settings Files")

        selectTab("Shortcuts", in: settings)
        XCTAssertTrue(settings.staticTexts["Show or hide Pad"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        expectValue(original, in: editor)
        attach(settings.screenshot(), name: "Pad Settings Shortcuts")

        // A native click returns from Settings without invoking document replacement or save.
        XCTAssertTrue(editor.exists, app.debugDescription)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        app.typeKey(.downArrow, modifierFlags: .command)
        let suffix = "\nStill editing after Settings."
        app.typeText(suffix)
        expectValue(original + suffix, in: editor)
        attach(app.screenshot(), name: "Pad editor after Settings")

        app.typeKey("n", modifierFlags: .command)
        expectValue("", in: editor)
        XCTAssertTrue(app.staticTexts["Untitled"].firstMatch.exists, app.debugDescription)
        app.typeText("Fresh disposable scratch")
        expectValue("Fresh disposable scratch", in: editor)
        attach(app.screenshot(), name: "Pad fresh file from Command N")

        app.typeKey(.escape, modifierFlags: [])
        let close = app.buttons["Close Pad"].firstMatch
        let dismissed = NSPredicate(format: "exists == false OR hittable == false")
        expectation(for: dismissed, evaluatedWith: close)
        waitForExpectations(timeout: 5)
    }

    func testFloatingFolderSheetCancellationAndMouseClose() {
        let app = launchPad(floating: true)
        defer { app.terminate() }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        let draft = "Disposable floating dialog draft"
        app.typeText(draft)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        selectTab("Files", in: settings)
        settings.buttons["Choose…"].click()
        let sheet = settings.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), app.debugDescription)
        let cancel = sheet.buttons["CancelButton"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(cancel.isHittable, app.debugDescription)
        attach(XCUIScreen.main.screenshot(), name: "Folder sheet above floating Settings and Pad")
        cancel.click()
        expectValue(draft, in: editor)
        let close = app.buttons["Close Pad"].firstMatch
        // Settings remains key: the first click must work on Pad's inactive toolbar.
        XCTAssertTrue(close.isEnabled, app.debugDescription)
        XCTAssertTrue(close.isHittable, app.debugDescription)
        close.click()
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false OR hittable == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, app.debugDescription)
    }

    func testGlobalShortcutOpensOverFinderAndReturnsFocus() {
        let app = launchPad()
        defer { app.terminate() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        selectTab("Shortcuts", in: settings)
        expectValue("⌃⌥⇧⌘P", in: settings.searchFields.firstMatch)
        attach(settings.screenshot(), name: "Effective development shortcut")
        let shortcutDescription = XCTAttachment(string: settings.debugDescription)
        shortcutDescription.name = "Effective shortcut accessibility state"
        shortcutDescription.lifetime = .keepAlways
        add(shortcutDescription)
        settings.buttons["_XCUI:CloseWindow"].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        let close = app.buttons["Close Pad"].firstMatch
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)

        // Finder can have no window; use its on-screen menu bar as the event target.
        let finderMenuBar = finder.menuBars.firstMatch
        XCTAssertTrue(finderMenuBar.waitForExistence(timeout: 5), finder.debugDescription)
        XCTAssertGreaterThan(finderMenuBar.frame.width, 0)
        finderMenuBar.typeKey("p", modifierFlags: [.control, .option, .command, .shift])
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed, app.debugDescription)
        attach(app.screenshot(), name: "Pad opened with development global shortcut")
        finderMenuBar.typeKey("p", modifierFlags: [.control, .option, .command, .shift])
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
    }

    func testCancelingNativeFilePanelsAndSharingPreservesScratch() {
        let app = launchPad(floating: true)
        defer { app.terminate() }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        var expected = "Disposable dialog test \(UUID().uuidString)"
        app.typeText(expected)
        expectValue(expected, in: editor)

        app.typeKey("s", modifierFlags: [.command, .shift])
        let saveCancel = app.buttons["CancelButton"].firstMatch
        XCTAssertTrue(saveCancel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(saveCancel.isHittable, app.debugDescription)
        saveCancel.click()
        expectValue(expected, in: editor)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("\nAfter canceled Save As.")
        expected += "\nAfter canceled Save As."
        expectValue(expected, in: editor)

        app.typeKey("o", modifierFlags: .command)
        let openCancel = app.buttons["CancelButton"].firstMatch
        XCTAssertTrue(openCancel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(openCancel.isHittable, app.debugDescription)
        openCancel.click()
        expectValue(expected, in: editor)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("\nAfter canceled Open.")
        expected += "\nAfter canceled Open."
        expectValue(expected, in: editor)

        app.buttons["Share"].firstMatch.click()
        let picker = app.popovers["ShareSheet.Popover"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThan(picker.frame.width, 0)
        let sharingState = XCTAttachment(string: app.debugDescription)
        sharingState.name = "Native sharing picker accessibility state"
        sharingState.lifetime = .keepAlways
        add(sharingState)
        attach(XCUIScreen.main.screenshot(), name: "Native sharing picker")
        app.typeKey(.escape, modifierFlags: [])
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        expectValue(expected, in: editor)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("\nAfter canceled Share.")
        expected += "\nAfter canceled Share."
        expectValue(expected, in: editor)
        attach(app.screenshot(), name: "Scratch preserved after native dialogs and sharing")
    }

    func testCustomEditingShortcutAndRestoreDefaults() {
        let app = launchPad()
        defer { app.terminate() }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.typeText("Disposable shortcut draft")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        selectTab("Shortcuts", in: settings)
        let recorder = settings.searchFields["editingShortcut.newFile"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 5), settings.debugDescription)
        expectValue("⌘N", in: recorder)
        recorder.click()
        app.typeKey("b", modifierFlags: [.command, .shift])
        expectValue("⇧⌘B", in: recorder)
        attach(settings.screenshot(), name: "Custom local editing shortcut")
        settings.buttons["_XCUI:CloseWindow"].click()
        editor.click()
        app.typeKey("n", modifierFlags: .command)
        expectValue("Disposable shortcut draft", in: editor)
        app.typeKey("b", modifierFlags: [.command, .shift])
        expectValue("", in: editor)
        app.typeText("Draft after custom shortcut")
        expectValue("Draft after custom shortcut", in: editor)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        selectTab("Shortcuts", in: settings)
        settings.buttons["Restore Defaults"].click()
        expectValue("⌘N", in: recorder)
        settings.buttons["_XCUI:CloseWindow"].click()
        editor.click()
        app.typeKey("b", modifierFlags: [.command, .shift])
        expectValue("Draft after custom shortcut", in: editor)
        app.typeKey("n", modifierFlags: .command)
        expectValue("", in: editor)
        attach(app.screenshot(), name: "Restored New Text File shortcut")
    }

    func testDockToggleKeepsSettingsAndDraftUsable() throws {
        let app = launchPad()
        defer { app.terminate() }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let draft = "Disposable Dock visibility draft"
        app.typeText(draft)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        selectTab("General", in: settings)
        let dock = settings.switches["showInDock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 5), settings.debugDescription)
        let testBundleID = try XCTUnwrap(Bundle(for: Self.self).bundleIdentifier)
        XCTAssertTrue(testBundleID.hasSuffix(".uitests"))
        let targetBundleID = String(testBundleID.dropLast(".uitests".count))
        let matchingProcesses = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
        XCTAssertEqual(matchingProcesses.count, 1)
        let process = try XCTUnwrap(matchingProcesses.first)
        let initialRegular = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "activationPolicy == %d", NSApplication.ActivationPolicy.regular.rawValue),
            object: process)
        XCTAssertEqual(XCTWaiter.wait(for: [initialRegular], timeout: 5), .completed)
        dock.click()
        let accessory = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "activationPolicy == %d", NSApplication.ActivationPolicy.accessory.rawValue),
            object: process)
        XCTAssertEqual(XCTWaiter.wait(for: [accessory], timeout: 5), .completed)
        selectTab("Files", in: settings)
        XCTAssertTrue(settings.staticTexts["Save when Pad closes"].firstMatch.waitForExistence(timeout: 5))
        expectValue(draft, in: editor)
        selectTab("General", in: settings)
        attach(settings.screenshot(), name: "Settings remains usable without Dock icon")
        dock.click()
        let regular = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "activationPolicy == %d", NSApplication.ActivationPolicy.regular.rawValue),
            object: process)
        XCTAssertEqual(XCTWaiter.wait(for: [regular], timeout: 5), .completed)
        selectTab("Shortcuts", in: settings)
        XCTAssertTrue(settings.staticTexts["Show or hide Pad"].firstMatch.waitForExistence(timeout: 5))
        settings.buttons["_XCUI:CloseWindow"].click()
        editor.click()
        expectValue(draft, in: editor)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText(" still editing")
        expectValue(draft + " still editing", in: editor)
        attach(app.screenshot(), name: "Draft preserved through Dock visibility changes")
    }

    private func launchPad(floating: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Launch overrides establish a deterministic initial state without changing saved values.
        app.launchArguments = ["-pad.saveAutomatically", "NO", "-pad.floating", floating ? "YES" : "NO",
                               "-showInDock", "YES", "-menuBarItem", "NO",
                               "-pad.editingShortcuts", "invalid",
                               "-KeyboardShortcuts_pad", #""{\"carbonKeyCode\":35,\"carbonModifiers\":6912}""#]
        app.launch()
        return app
    }

    private func selectTab(_ title: String, in settings: XCUIElement) {
        let tab = settings.toolbars.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), settings.debugDescription)
        XCTAssertTrue(tab.isHittable, settings.debugDescription)
        tab.click()
    }

    private func expectValue(_ expected: String, in element: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected \(String(reflecting: expected)); actual \(String(describing: element.value))",
                       file: file, line: line)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
