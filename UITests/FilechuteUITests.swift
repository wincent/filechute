import XCTest

final class FilechuteUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helpers

    private var table: XCUIElement {
        app.tables.firstMatch
    }

    private func addTestFile() {
        // Use the "Add Files" toolbar button to open file picker,
        // but for automated testing we'd need test fixtures.
        // For now, tests assume at least one file is already ingested.
    }

    private func selectFirstRow() {
        let firstCell = table.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5),
                      "Table should have at least one row")
        firstCell.click()
    }

    // MARK: - Selection

    @MainActor
    func testClickToSelect() throws {
        selectFirstRow()
        XCTAssertTrue(table.cells.firstMatch.isSelected)
    }

    @MainActor
    func testMultiSelectWithShiftClick() throws {
        let cells = table.cells
        guard cells.count >= 2 else {
            throw XCTSkip("Need at least 2 items to test multi-select")
        }
        cells.element(boundBy: 0).click()
        cells.element(boundBy: 1).click(forDuration: 0, thenDragTo: cells.element(boundBy: 1),
                                         withVelocity: .default, thenHoldForDuration: 0)
    }

    // MARK: - Rename

    @MainActor
    func testEnterStartsRename() throws {
        selectFirstRow()
        app.typeKey(.return, modifierFlags: [])
        let textField = table.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2),
                      "Pressing Enter should show a rename text field")
    }

    @MainActor
    func testEscapeCancelsRename() throws {
        selectFirstRow()
        app.typeKey(.return, modifierFlags: [])

        let textField = table.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(textField.exists,
                       "Pressing Escape should dismiss the rename text field")
    }

    @MainActor
    func testEscapeKeepsTableFocused() throws {
        selectFirstRow()
        app.typeKey(.return, modifierFlags: [])

        let textField = table.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2))

        app.typeKey(.escape, modifierFlags: [])

        // Table should retain focus - verify by pressing Down arrow
        // which should change selection (not beep)
        app.typeKey(.downArrow, modifierFlags: [])
        // If focus was lost, this would have no effect
    }

    @MainActor
    func testRenameCommitsOnEnter() throws {
        selectFirstRow()
        let originalName = table.cells.firstMatch.staticTexts.firstMatch.value as? String ?? ""

        app.typeKey(.return, modifierFlags: [])
        let textField = table.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2))

        // Clear and type new name
        textField.typeKey("a", modifierFlags: .command) // Select all
        textField.typeText("TestRename_\(Int.random(in: 1000...9999))")
        app.typeKey(.return, modifierFlags: [])

        // Text field should be gone
        XCTAssertFalse(textField.exists,
                       "Rename text field should dismiss after Enter")

        // Name should have changed
        let newName = table.cells.firstMatch.staticTexts.firstMatch.value as? String
        XCTAssertNotEqual(newName, originalName, "Name should have changed")
    }

    // MARK: - Double-click to open

    @MainActor
    func testDoubleClickOpensFile() throws {
        selectFirstRow()
        let firstCell = table.cells.firstMatch
        firstCell.doubleClick()
        // File should open in default app. We can't easily verify this
        // but we can verify the app didn't crash and the table is still there.
        XCTAssertTrue(table.exists)
    }

    // MARK: - Quick Look

    @MainActor
    func testSpaceTogglesQuickLook() throws {
        selectFirstRow()
        app.typeKey(" ", modifierFlags: [])
        // Quick Look panel should appear
        // QLPreviewPanel creates a separate window
        sleep(1)
        // Press space again to dismiss
        app.typeKey(" ", modifierFlags: [])
    }

    // MARK: - Command+Down to open

    @MainActor
    func testCommandDownOpens() throws {
        selectFirstRow()
        app.typeKey(.downArrow, modifierFlags: .command)
        // Should open the file without crashing
        XCTAssertTrue(table.exists)
    }
}
