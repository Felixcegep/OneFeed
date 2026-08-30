//
//  MonoRssUITests.swift
//  MonoRssUITests
//
//  Created by Felix Lachapelle on 2026-08-29.
//

import XCTest

final class MonoRssUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore"]
        app.launch()
        XCTAssertTrue(app.navigationBars["OneFeed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["VMs Won’t Contain Cyber-Capable Agents"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Swift concurrency without the noise"].waitForExistence(timeout: 2))
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCaptureAllMVPscreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore"]
        app.launch()

        XCTAssertTrue(app.navigationBars["OneFeed"].waitForExistence(timeout: 5))
        capture("01-Current", app: app)

        app.buttons["Read"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["TRAIL OF BITS"].waitForExistence(timeout: 5))
        capture("02-Reader", app: app)
        app.buttons["Close"].tap()

        openMenuDestination("Saved", app: app)
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 3))
        capture("03-Saved", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openMenuDestination("History", app: app)
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        capture("04-History", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openMenuDestination("Sources", app: app)
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 3))
        capture("05-Sources", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openMenuDestination("Settings", app: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture("06-Settings", app: app)
    }

    @MainActor
    private func openMenuDestination(_ name: String, app: XCUIApplication) {
        app.buttons["current.navigationMenu"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 2))
        app.buttons[name].tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
