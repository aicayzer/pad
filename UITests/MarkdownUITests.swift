import AppKit
import XCTest

@MainActor
final class MarkdownUITests: XCTestCase {
    func testMarkdownPasteFormattingSaveReopenAndSettingsReturn() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = launchPad()
        defer { app.terminate() }
        waitForEditor(app)

        let source = "# Disposable Markdown\n\nPasted **bold** and _italic_.\n\n- First item\n- Second item\n\nFinal paragraph"
        paste(source, into: app)
        attach(app.screenshot(), name: "Markdown pasted as formatted content")
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Disposable Markdown"].firstMatch.exists ||
                      web.textViews.firstMatch.exists, app.debugDescription)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("b", modifierFlags: .command)
        app.typeText("Bold keyboard text")
        app.typeKey("b", modifierFlags: .command)
        app.typeText(" ")
        app.typeKey("i", modifierFlags: .command)
        app.typeText("Italic keyboard text")
        app.typeKey("i", modifierFlags: .command)
        app.typeText(" Example")
        app.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        app.typeKey("k", modifierFlags: .command)
        let urlField = app.textFields["Link URL"].firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), app.debugDescription)
        urlField.click()
        paste("https://example.com/padpad-ui-test", into: app)
        XCTAssertEqual(urlField.value as? String, "https://example.com/padpad-ui-test")
        let addLink = app.buttons["Add Link"].firstMatch
        XCTAssertTrue(addLink.isEnabled, app.debugDescription)
        addLink.click()
        attach(app.screenshot(), name: "Markdown toolbar and keyboard formatting")

        let saved = try saveAs(app, directory: directory)
        var contents = try String(contentsOf: saved, encoding: .utf8)
        XCTAssertEqual(saved.pathExtension, "md")
        XCTAssertTrue(contents.contains("# Disposable Markdown"), contents)
        XCTAssertTrue(contents.contains("**bold**"), contents)
        XCTAssertTrue(contents.contains("**Bold keyboard text**"), contents)
        XCTAssertTrue(contents.contains("*Italic keyboard text*"), contents)
        XCTAssertTrue(contents.contains("https://example.com/padpad-ui-test"), contents)

        app.typeKey("n", modifierFlags: .command)
        waitForEditor(app)
        app.typeText("New document must not leak")
        app.typeKey("o", modifierFlags: .command)
        open(saved, in: app)
        waitForEditor(app)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("\nAfter reopen")
        app.typeKey("s", modifierFlags: .command)
        waitForFile(saved, containing: "After reopen")
        contents = try String(contentsOf: saved, encoding: .utf8)
        XCTAssertFalse(contents.contains("New document must not leak"), contents)
        attach(app.screenshot(), name: "Saved Markdown reopened and edited")

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        let files = settings.toolbars.buttons["Files"].firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 5), app.debugDescription)
        files.click()
        attach(settings.screenshot(), name: "Settings while formatted Markdown is open")
        settings.buttons["_XCUI:CloseWindow"].click()
        web.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)).click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("\nAfter Settings")
        app.typeKey("s", modifierFlags: .command)
        waitForFile(saved, containing: "After Settings")
        attach(app.screenshot(), name: "Formatted Markdown retained after Settings")

        let undoText = " Undoable addition"
        app.typeText(undoText)
        app.typeKey("s", modifierFlags: .command)
        waitForFile(saved, containing: undoText)
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("s", modifierFlags: .command)
        let undone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? String(contentsOf: saved, encoding: .utf8).contains(undoText)) == false
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [undone], timeout: 5), .completed)
        app.typeKey("z", modifierFlags: [.command, .shift])
        app.typeKey("s", modifierFlags: .command)
        waitForFile(saved, containing: undoText)

        app.typeKey(",", modifierFlags: .command)
        settings.toolbars.buttons["General"].click()
        let appearance = settings.popUpButtons["appearance"].firstMatch
        let originalAppearance = try XCTUnwrap(appearance.value as? String)
        appearance.click()
        app.menuItems["Dark"].click()
        attach(app.screenshot(), name: "Formatted editor and Settings in Dark appearance")
        appearance.click()
        app.menuItems[originalAppearance].click()
    }

    func testImmediateTypingSavingAndNewDocumentIsolation() throws {
        let firstDirectory = try temporaryDirectory()
        let secondDirectory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let app = launchPad()
        defer { app.terminate() }
        // No editor click or readiness wait: launch and document replacement own initial focus.
        let firstText = "Immediate Markdown \(UUID().uuidString)"
        app.typeText(firstText)
        let first = try saveAs(app, directory: firstDirectory)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), firstText)

        app.typeKey("n", modifierFlags: .command)
        let secondText = "Second isolated Markdown \(UUID().uuidString)"
        app.typeText(secondText)
        let second = try saveAs(app, directory: secondDirectory)
        let contents = try String(contentsOf: second, encoding: .utf8)
        XCTAssertEqual(contents.trimmingCharacters(in: .whitespacesAndNewlines), secondText)
        XCTAssertFalse(contents.contains(firstText))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), firstText)
        attach(app.screenshot(), name: "Immediate Markdown typing and saved document isolation")
    }

    private func launchPad() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pad.format", "md", "-pad.saveAutomatically", "NO", "-pad.floating", "NO",
                               "-showInDock", "YES", "-menuBarItem", "NO", "-pad.editingShortcuts", "invalid"]
        app.launch()
        return app
    }

    private func waitForEditor(_ app: XCUIApplication) {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        let bold = app.buttons["Bold"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: bold)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, app.debugDescription)
    }

    private func paste(_ source: String, into app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "pad-markdown-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func saveAs(_ app: XCUIApplication, directory: URL) throws -> URL {
        app.typeKey("s", modifierFlags: [.command, .shift])
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), app.debugDescription)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(directory.path)
        app.typeKey(.return, modifierFlags: [])
        let save = sheet.buttons["OKButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        save.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, app.debugDescription)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try XCTUnwrap(files.first { $0.pathExtension == "md" })
    }

    private func open(_ file: URL, in app: XCUIApplication) {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), app.debugDescription)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(.return, modifierFlags: [])
        let open = sheet.buttons["OKButton"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        open.click()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, app.debugDescription)
    }

    private func waitForFile(_ file: URL, containing text: String) {
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? String(contentsOf: file, encoding: .utf8).contains(text)) == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed, "Saved Markdown did not contain \(text)")
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
