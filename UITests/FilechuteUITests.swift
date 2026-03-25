import XCTest

final class FilechuteUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-StoreBaseDirectory", "/tmp/filechute-uitest",
            "-UserDefaultsSuite", "dev.wincent.Filechute.UITesting",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func element(_ identifier: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any)[identifier].firstMatch
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
    func testMainWindowShowsSidebarAndToolbar() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // Sidebar navigation elements
        XCTAssertTrue(
            element("sidebar-all-items").waitForExistence(timeout: 5),
            "Sidebar should show All Items"
        )
        XCTAssertTrue(
            element("sidebar-trash").waitForExistence(timeout: 5),
            "Sidebar should show Trash"
        )
        XCTAssertTrue(
            element("sidebar-store").waitForExistence(timeout: 5),
            "Sidebar should show store name"
        )

        // Toolbar controls
        XCTAssertTrue(
            element("view-mode-picker").waitForExistence(timeout: 5),
            "Toolbar should show view mode picker"
        )
        XCTAssertTrue(
            element("add-files-button").exists,
            "Toolbar should show add files button"
        )
        XCTAssertTrue(
            element("toggle-inspector").exists,
            "Toolbar should show inspector toggle"
        )
        XCTAssertTrue(
            element("search-field").exists,
            "Toolbar should show search field"
        )
    }

    @MainActor
    func testEmptyStoreShowsEmptyState() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        XCTAssertTrue(
            element("empty-state").waitForExistence(timeout: 5),
            "Empty store should show empty state view"
        )
    }

    @MainActor
    func testLogWindowShowsEntries() throws {
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))

        app.typeKey("l", modifierFlags: [.command, .option])

        let logWindow = app.windows["Log"]
        XCTAssertTrue(
            logWindow.waitForExistence(timeout: 5),
            "Log window should open"
        )

        // Verify log window controls exist via accessibility identifiers
        XCTAssertTrue(
            element("log-category-picker", in: logWindow).waitForExistence(timeout: 5),
            "Log window should show category picker"
        )
        XCTAssertTrue(
            element("log-level-picker", in: logWindow).exists,
            "Log window should show level picker"
        )
        XCTAssertTrue(
            element("log-clear-button", in: logWindow).exists,
            "Log window should show clear button"
        )
        XCTAssertTrue(
            element("log-auto-scroll", in: logWindow).exists,
            "Log window should show auto-scroll toggle"
        )

        // Verify a database log entry appeared from app initialization
        let databaseEntry = logWindow.staticTexts["database"].firstMatch
        XCTAssertTrue(
            databaseEntry.waitForExistence(timeout: 5),
            "Log should contain a database category entry"
        )

        logWindow.typeKey("w", modifierFlags: .command)
        sleep(1)
        XCTAssertFalse(logWindow.exists, "Log window should close")
    }
}
