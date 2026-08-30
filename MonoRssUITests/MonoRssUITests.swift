import XCTest

final class MonoRssUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Recent"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["VMs Won’t Contain Cyber-Capable Agents"].exists)
        app.tabBars.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Next"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Swift concurrency without the noise"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCaptureAllMVPscreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Recent"].waitForExistence(timeout: 5))
        capture("01-Recent", app: app)

        app.tabBars.buttons["Folders"].tap()
        XCTAssertTrue(app.navigationBars["Folders"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Development"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Security"].exists)
        capture("02-Folders", app: app)

        app.otherElements["folder-Security"].tap()
        XCTAssertTrue(app.navigationBars["Security"].waitForExistence(timeout: 2))
        capture("03-Folder-Articles", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Next"].tap()
        XCTAssertTrue(app.navigationBars["Next"].waitForExistence(timeout: 3))
        capture("04-Next", app: app)

        app.buttons["Read"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["TRAIL OF BITS"].waitForExistence(timeout: 5))
        capture("05-Reader", app: app)
        app.buttons["Close"].tap()

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 3))
        capture("06-Saved", app: app)

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 3))
        capture("07-Library", app: app)

        app.buttons["Sources"].tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 3))
        capture("08-Sources", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture("09-Settings", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
