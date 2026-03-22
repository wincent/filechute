import XCTest

final class FilechuteUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    @MainActor
    func testAppLaunches() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "App window should appear after launch"
        )
    }

    @MainActor
    func testLogWindowShowsEntries() throws {
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))

        // Open the log window via Cmd+Option+L
        app.typeKey("l", modifierFlags: [.command, .option])

        let logWindow = app.windows["Log"]
        XCTAssertTrue(
            logWindow.waitForExistence(timeout: 5),
            "Log window should open"
        )

        // App initialization logs "Opened database at ..." with category "database"
        let databaseEntry = logWindow.staticTexts["database"].firstMatch
        XCTAssertTrue(
            databaseEntry.waitForExistence(timeout: 5),
            "Log should contain a database category entry"
        )

        // Close the log window
        logWindow.typeKey("w", modifierFlags: .command)
        sleep(1)
        XCTAssertFalse(logWindow.exists, "Log window should close")
    }
}
