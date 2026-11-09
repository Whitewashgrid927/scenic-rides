import XCTest

final class HomeScreenTests: XCTestCase {
    @MainActor
    func testHomeAndRoutePreviewHandoff() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SCENIC_ROUTE_TEST_SCENARIO"] = "ready"
        app.launch()
        XCTAssertTrue(app.buttons["startingPoint"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Returns to your starting point"].exists)
        XCTAssertEqual(app.switches.count, 0)

        let picker = app.segmentedControls["rideLength"]
        XCTAssertTrue(picker.buttons["60 min"].isSelected)
        picker.buttons["90 min"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["routeTarget"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["routeTarget"].label.contains("90 min budget"))
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["routeReturn"].label.contains("Austin, TX"))
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(picker.buttons["90 min"].isSelected)
        saveScreenshot(app, name: "Home screen")
    }

    @MainActor
    func testLocationPickerAndCancelPreserveHome() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["startingPoint"].tap()
        XCTAssertTrue(app.navigationBars["Starting point"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["useMyLocation"].exists)
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["startingPoint"].exists)
        app.buttons["startingPoint"].tap()
        app.buttons["chooseAustin"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeTextKeepsPrimaryActionReachable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SCENIC_ROUTE_TEST_SCENARIO"] = "ready"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let action = app.buttons["findRide"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        for _ in 0..<4 {
            if action.frame.maxY <= app.frame.maxY - 40 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(action.isHittable)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY - 40)
        saveScreenshot(app, name: "Large text home screen")
        action.tap()
        XCTAssertTrue(app.navigationBars["Choose your loop"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLivePlaceSearchUpdatesStartingPoint() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["startingPoint"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Zilker Botanical Garden")
        let result = app.staticTexts.matching(NSPredicate(format: "label == %@", "Zilker Botanical Garden")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
        result.tap()
        XCTAssertTrue(app.buttons["startingPoint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startingPoint"].label.contains("Zilker Botanical Garden"))
    }

    @MainActor
    func testLocationDenialLeavesManualSelectionAvailable() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        XCTAssertTrue(app.buttons["startingPoint"].waitForExistence(timeout: 15))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertEqual(system.alerts.count, 0, "Launching the home screen must not request location access.")
        app.buttons["startingPoint"].tap()
        app.buttons["useMyLocation"].tap()
        let deny = system.alerts.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow"
        )).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        XCTAssertTrue(app.staticTexts["Location access is off. You can search for a starting point instead."].waitForExistence(timeout: 5))
        app.buttons["chooseAustin"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
