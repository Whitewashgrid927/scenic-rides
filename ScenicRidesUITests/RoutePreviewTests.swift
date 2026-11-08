import XCTest

final class RoutePreviewTests: XCTestCase {
    @MainActor
    func testPreviewShowsActualEstimateStopsAndAnotherLoop() throws {
        let app = launch(scenario: "ready")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["routeName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["routeName"].label, "Hills & river")
        XCTAssertTrue(app.staticTexts["routeEstimate"].label.contains("40 min"))
        XCTAssertTrue(app.staticTexts["routeTarget"].label.contains("60 min target"))
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.navigationBars["Route stops"].waitForExistence(timeout: 5))
        let start = app.descendants(matching: .any)["routeStop-0"].firstMatch
        let end = app.descendants(matching: .any)["routeStop-4"].firstMatch
        XCTAssertTrue(start.label.contains("Austin, TX"))
        XCTAssertTrue(end.label.contains("Austin, TX"))
        app.buttons["Done"].tap()
        app.buttons["anotherRoute"].tap()
        let changed = NSPredicate(format: "label == %@", "Around Lake Austin")
        expectation(for: changed, evaluatedWith: app.staticTexts["routeName"])
        waitForExpectations(timeout: 10)
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailureCanRetryWithoutLosingPreferences() throws {
        let app = launch(scenario: "retry")
        app.segmentedControls["rideLength"].buttons["30 min"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["routeError"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["routeEstimate"].exists)
        XCTAssertFalse(app.buttons["viewRouteStops"].exists)
        app.buttons["retryRoute"].tap()
        XCTAssertTrue(app.staticTexts["routeName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["routeName"].label, "Parks & skyline")
        XCTAssertTrue(app.staticTexts["routeTarget"].label.contains("30 min target"))
    }

    @MainActor
    func testLoadingCanBeDismissed() throws {
        let app = launch(scenario: "loading")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["Finding the scenic way…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["viewRouteStops"].exists)
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeTextKeepsRouteActionsReachable() throws {
        let app = launch(scenario: "ready", largeText: true)
        scrollTo(app.buttons["findRide"], in: app)
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["routeName"].waitForExistence(timeout: 10))
        let stops = app.buttons["viewRouteStops"]
        scrollTo(stops, in: app)
        XCTAssertTrue(stops.isHittable)
        XCTAssertLessThanOrEqual(stops.frame.maxY, app.frame.maxY - 30)
        screenshot(app, name: "Route preview large text fixture")
        stops.tap()
        XCTAssertTrue(app.navigationBars["Route stops"].waitForExistence(timeout: 5))
    }

    /// A separate network smoke test; all other preview tests use deterministic fixtures.
    @MainActor
    func testLiveAustinLoops() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 15))
        app.buttons["findRide"].tap()
        for name in ["Hills & river", "Around Lake Austin", "Parks & skyline"] {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label == %@", name),
                object: app.staticTexts["routeName"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed, app.debugDescription)
            XCTAssertEqual(app.staticTexts["routeName"].label, name)
            XCTAssertTrue(app.staticTexts["routeEstimate"].exists)
            XCTAssertTrue(app.buttons["fitRoute"].isEnabled)
            screenshot(app, name: "Live Austin — \(name)")
            if name != "Parks & skyline" {
                app.buttons["anotherRoute"].tap()
            }
        }
    }

    @MainActor
    private func launch(scenario: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SCENIC_ROUTE_TEST_SCENARIO"] = scenario
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable, element.frame.maxY <= app.frame.maxY - 40 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
