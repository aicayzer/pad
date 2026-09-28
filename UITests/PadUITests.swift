import XCTest

@MainActor
final class PadUITests: XCTestCase {
    func testSettingsPreservesScratchAndEditorAcceptsInput() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // NSArgumentDomain overrides leave saved preferences and existing documents untouched.
        app.launchArguments = ["-pad.saveAutomatically", "NO", "-pad.floating", "NO",
                               "-showInDock", "YES", "-menuBarItem", "NO"]
        app.launch()
        defer { app.terminate() }

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
        let original = "Disposable Pad UI test \(UUID().uuidString)"
        // Do not click the editor first: launch must establish its keyboard focus.
        app.typeText(original)
        expectValue(original, in: editor)
        attach(app.screenshot(), name: "Pad editor after launch")

        app.typeKey(",", modifierFlags: .command)
        let login = app.checkBoxes["Open at login"].firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(login.isHittable, app.debugDescription)
        expectValue(original, in: editor)
        attach(app.screenshot(), name: "Pad Settings from keyboard")

        // A native click returns from Settings without invoking document replacement or save.
        XCTAssertTrue(editor.isHittable, app.debugDescription)
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        let suffix = "\nStill editing after Settings."
        app.typeText(suffix)
        expectValue(original + suffix, in: editor)
        attach(app.screenshot(), name: "Pad editor after Settings")

        app.typeKey(.escape, modifierFlags: [])
        let close = app.buttons["Close Pad"].firstMatch
        let dismissed = NSPredicate(format: "exists == false OR hittable == false")
        expectation(for: dismissed, evaluatedWith: close)
        waitForExpectations(timeout: 5)
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
