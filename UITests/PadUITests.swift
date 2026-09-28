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

    func testGlobalShortcutOpensOverFinderAndReturnsFocus() {
        let app = launchPad()
        defer { app.terminate() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        let close = app.buttons["Close Pad"].firstMatch
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)

        finder.typeKey("p", modifierFlags: [.control, .option, .command, .shift])
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed, app.debugDescription)
        attach(app.screenshot(), name: "Pad opened with development global shortcut")
        close.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
    }

    private func launchPad() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // NSArgumentDomain overrides leave saved preferences and existing documents untouched.
        app.launchArguments = ["-pad.saveAutomatically", "NO", "-pad.floating", "NO",
                               "-showInDock", "YES", "-menuBarItem", "NO",
                               "-KeyboardShortcuts_pad", #"{"carbonKeyCode":35,"carbonModifiers":6912}"#]
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
