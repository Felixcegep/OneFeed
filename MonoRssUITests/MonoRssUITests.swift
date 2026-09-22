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

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Queue"].exists)
        XCTAssertTrue(app.tabBars.buttons["Feed"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertFalse(app.tabBars.buttons["Library"].exists)
        XCTAssertFalse(app.tabBars.buttons["Next"].exists)
        XCTAssertFalse(app.tabBars.buttons["Saved"].exists)
        XCTAssertFalse(app.tabBars.buttons["Later"].exists)

        app.tabBars.buttons["Queue"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["Queue"].buttons["Add"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Why SQLite is so reliable"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Feed"].tap()
        XCTAssertTrue(app.navigationBars["Feed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["New articles"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Smart Feeds"].exists)
        XCTAssertTrue(app.staticTexts["Development"].exists || app.staticTexts["Security"].exists)

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["VMs Won’t Contain Cyber-Capable Agents"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testCaptureAllScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        capture("01-Today", app: app)

        app.staticTexts["VMs Won’t Contain Cyber-Capable Agents"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        capture("02-Reader", app: app)
        app.buttons["Close"].tap()

        app.tabBars.buttons["Queue"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 3))
        capture("03-Queue", app: app)

        app.navigationBars["Queue"].buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Add to Queue"].waitForExistence(timeout: 2))
        capture("04-AddToQueue", app: app)
        app.navigationBars["Add to Queue"].buttons["Cancel"].tap()

        app.tabBars.buttons["Feed"].tap()
        XCTAssertTrue(app.navigationBars["Feed"].waitForExistence(timeout: 3))
        capture("05-Feed", app: app)

        app.staticTexts["New articles"].tap()
        XCTAssertTrue(app.navigationBars["New articles"].waitForExistence(timeout: 3))
        capture("06-NewArticles", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The row identifier is inherited by its icon and navigation buttons.
        // Target the folder destination, not the separate icon-edit action.
        let securityFolder = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "folder-Security", "Security")
        ).firstMatch
        XCTAssertTrue(securityFolder.waitForExistence(timeout: 2))
        securityFolder.tap()
        XCTAssertTrue(app.navigationBars["Security"].waitForExistence(timeout: 2))
        capture("07-Folder-Articles", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.staticTexts["Manage sources"].tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 3))
        capture("08-Sources", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Queue"].tap()
        app.navigationBars["Queue"].buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        capture("09-History", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture("10-Settings", app: app)

        XCTAssertFalse(app.tabBars.buttons["Library"].exists)
    }

    @MainActor
    func testCaptureEmptyQueueAndOnboarding() throws {
        let empty = XCUIApplication()
        empty.launchArguments = ["-uiTesting", "-inMemoryStore", "-uiTestingEmptyQueue"]
        empty.launch()
        XCTAssertTrue(empty.tabBars.buttons["Queue"].waitForExistence(timeout: 5))
        empty.tabBars.buttons["Queue"].tap()
        XCTAssertTrue(empty.navigationBars["Queue"].waitForExistence(timeout: 3))
        XCTAssertTrue(empty.buttons["Open Today"].waitForExistence(timeout: 2))
        capture("11-Queue-Empty", app: empty)
        empty.terminate()

        let onboarding = XCUIApplication()
        onboarding.launchArguments = ["-uiTesting", "-inMemoryStore", "-uiTestingOnboarding"]
        onboarding.launch()
        XCTAssertTrue(onboarding.buttons["Continue"].waitForExistence(timeout: 5))
        capture("12-Onboarding", app: onboarding)
    }

    @MainActor
    func testCaptureLongLayouts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore", "-uiTestingLayoutStress"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.staticTexts["VMs Won’t Contain Cyber-Capable Agents"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        capture("13-Reader-Rich", app: app)
        app.webViews.firstMatch.swipeUp()
        capture("14-Reader-Scrolled", app: app)
        app.buttons["Close"].tap()

        app.tabBars.buttons["Queue"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 3))
        capture("15-Queue-Multiple", app: app)
        let last = app.staticTexts["Last saved layout example"]
        for _ in 0..<24 {
            if last.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(last.isHittable, "The last saved article must be reachable above the tab bar")
        capture("16-Queue-Bottom", app: app)
    }

    @MainActor
    func testCaptureSettingsDestinations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-inMemoryStore"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()

        let destinations = ["Reading", "Accounts & Sync", "Storage", "Video & AI", "Import & Export", "About"]
        for (index, title) in destinations.enumerated() {
            let destination = app.staticTexts[title].firstMatch
            for _ in 0..<12 {
                if destination.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(destination.isHittable, "Settings destination must be reachable: \(title)")
            destination.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            if title == "Reading" {
                XCTAssertTrue(app.staticTexts["Reading preview"].waitForExistence(timeout: 2))
            }
            if title == "Import & Export" {
                XCTAssertTrue(app.buttons["Import OPML"].waitForExistence(timeout: 2))
            }
            if title == "Video & AI" {
                XCTAssertTrue(app.buttons["Experimental librarian"].waitForExistence(timeout: 2))
            }
            capture("\(17 + index)-Settings-\(title.replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-"))", app: app)
            if title == "Accounts & Sync" {
                let connect = app.buttons["Connect FreshRSS"]
                XCTAssertTrue(connect.waitForExistence(timeout: 3))
                connect.tap()
                XCTAssertTrue(app.navigationBars["Connect FreshRSS"].waitForExistence(timeout: 3))
                capture("24-Connect-FreshRSS", app: app)
                app.buttons["Cancel"].tap()
                XCTAssertTrue(app.navigationBars["Accounts & Sync"].waitForExistence(timeout: 3))
            }
            app.navigationBars[title].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let folder = URL(fileURLWithPath: "/tmp/onefeed-uitest-screenshots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
