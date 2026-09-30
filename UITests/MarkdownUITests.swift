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
        XCTAssertFalse(app.buttons["Bold"].exists, "Formatting starts hidden")

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
        let suffix = " Immediate Markdown \(UUID().uuidString)"
        let firstText = "é" + suffix
        app.typeKey("e", modifierFlags: .option)
        app.typeKey("e", modifierFlags: [])
        app.typeText(suffix)
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

    func testFormattingTogglePreservesSelectionAndStartsHiddenEachLaunch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = launchPad()
        defer { app.terminate() }
        waitForEditor(app)
        let toggle = app.buttons["formattingToggle"].firstMatch
        XCTAssertEqual(toggle.value as? String, "Hidden")
        XCTAssertFalse(app.buttons["Bold"].exists)
        app.typeText("Selected text")
        app.typeKey("a", modifierFlags: .command)
        let editorFrame = app.webViews.firstMatch.frame
        toggle.click()
        let bold = app.buttons["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "Shown")
        XCTAssertEqual(bold.frame.midY, toggle.frame.midY, accuracy: 2, "Formatting belongs in the top toolbar")
        XCTAssertLessThan(bold.frame.maxX, toggle.frame.minX)
        XCTAssertEqual(app.webViews.firstMatch.frame.minY, editorFrame.minY, accuracy: 1, "Showing formatting must not add an editor row")
        XCTAssertEqual(app.webViews.firstMatch.frame.height, editorFrame.height, accuracy: 1)
        app.webViews.firstMatch.hover()
        attach(app.dialogs.firstMatch.screenshot(), name: "Formatting centered in the top toolbar without moving the editor")
        bold.click()
        toggle.click()
        XCTAssertFalse(bold.exists)
        XCTAssertEqual(toggle.value as? String, "Hidden")
        // No editor click: toggling chrome must preserve the selected range and keyboard focus.
        app.typeText("Replacement")
        let saved = try saveAs(app, directory: directory)
        let replacement = try String(contentsOf: saved, encoding: .utf8)
        XCTAssertEqual(replacement.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines), "Replacement")
        attach(app.screenshot(), name: "Hidden formatting retains editing focus and selection")
        toggle.click()
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        waitForEditor(app)
        XCTAssertFalse(app.buttons["Bold"].exists, "Formatting visibility is not persisted between launches")
        XCTAssertEqual(app.buttons["formattingToggle"].firstMatch.value as? String, "Hidden")
    }

    func testNarrowToolbarOverflowFormatsSelectedParagraphAndSaves() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = launchPad()
        defer { app.terminate() }
        waitForEditor(app)
        app.typeText("Keep plain\n\nSelected text")
        app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        let toggle = app.buttons["formattingToggle"].firstMatch
        toggle.click()

        let window = app.dialogs.firstMatch
        let originalFrame = window.frame
        let resizeHandle = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        let narrowCorner = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 518, dy: originalFrame.height - 2))
        resizeHandle.press(forDuration: 0.1, thenDragTo: narrowCorner)
        XCTAssertLessThanOrEqual(window.frame.width, 540, "The window must reach its narrow layout")

        let overflow = app.menuButtons["formattingOverflow"].firstMatch
        XCTAssertTrue(overflow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(overflow.isHittable)
        XCTAssertEqual(overflow.frame.midY, toggle.frame.midY, accuracy: 2)
        XCTAssertLessThan(overflow.frame.maxX, toggle.frame.minX)
        XCTAssertTrue(app.buttons["Save"].firstMatch.isHittable)
        attach(app.dialogs.firstMatch.screenshot(), name: "Narrow top toolbar keeps formatting overflow and Save available")
        overflow.click()
        let quote = app.menuItems["Quote"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 5), app.debugDescription)
        quote.click()

        let saved = try saveAs(app, directory: directory)
        let contents = try String(contentsOf: saved, encoding: .utf8)
        XCTAssertEqual(contents.trimmingCharacters(in: .whitespacesAndNewlines), "Keep plain\n\n<br />\n\n> Selected text")
    }

    func testAuthoredBlankParagraphsSurviveFileSwitchAndRepeatedReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = launchPad()
        defer { app.terminate() }
        waitForEditor(app)
        app.typeText("- First item")
        for _ in 0..<4 { app.typeKey(.return, modifierFlags: []) }
        app.typeText("- Second item")
        for _ in 0..<4 { app.typeKey(.return, modifierFlags: []) }
        attach(app.dialogs.firstMatch.screenshot(), name: "Authored blank paragraphs between lists and at the end")
        let saved = try saveAs(app, directory: directory)
        let original = try String(contentsOf: saved, encoding: .utf8)
        let spacers = original.components(separatedBy: "<br />").count - 1
        XCTAssertGreaterThanOrEqual(spacers, 4, original)
        XCTAssertTrue(original.contains("- First item"), original)
        XCTAssertTrue(original.contains("- Second item"), original)

        for cycle in 1...2 {
            app.typeKey("n", modifierFlags: .command)
            waitForEditor(app)
            app.typeText("A different disposable draft")
            app.typeKey("o", modifierFlags: .command)
            open(saved, in: app)
            waitForEditor(app)
            app.typeKey(.downArrow, modifierFlags: .command)
            app.typeText("Continued editing")
            app.typeKey("s", modifierFlags: .command)
            waitForFile(saved, containing: "Continued editing")
            let edited = try String(contentsOf: saved, encoding: .utf8)
            XCTAssertEqual(edited.components(separatedBy: "<br />").count - 1, spacers - 1, edited)
            // Restore the trailing empty paragraph and force a fresh serialization.
            app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
            app.typeKey(.delete, modifierFlags: [])
            app.typeKey("s", modifierFlags: .command)
            let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (try? String(contentsOf: saved, encoding: .utf8)) == original
            }, object: nil)
            _ = XCTWaiter.wait(for: [stable], timeout: 5)
            let restored = try String(contentsOf: saved, encoding: .utf8)
            if restored != original {
                let evidence = XCTAttachment(string: "Expected: \(String(reflecting: original))\nActual: \(String(reflecting: restored))")
                evidence.name = "Exact Markdown after reopen cycle \(cycle)"
                evidence.lifetime = .keepAlways
                add(evidence)
            }
            XCTAssertEqual(restored, original, "Authored spacing changed on reopen cycle \(cycle)")
            attach(app.dialogs.firstMatch.screenshot(), name: "Blank paragraphs retained after reopen cycle \(cycle)")
        }
    }

    private func launchPad() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pad.onboardingCompleted", "YES", "-pad.format", "md", "-pad.saveAutomatically", "NO", "-pad.floating", "NO",
                               "-showInDock", "YES", "-menuBarItem", "NO", "-pad.editingShortcuts", "invalid"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        return app
    }

    private func waitForEditor(_ app: XCUIApplication) {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        let toggle = app.buttons["formattingToggle"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: toggle)
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
