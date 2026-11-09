import XCTest

final class RoutePreviewTests: XCTestCase {
    @MainActor
    func testSwipeChangesSelectedRouteAndItsItinerary() throws {
        let app = launch(scenario: "ready")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["routeCard-0"].label.contains("40 min"))
        XCTAssertTrue(app.buttons["routePage-0"].isSelected)
        app.scrollViews["routeCards"].swipeLeft()
        waitSelected(app.buttons["routePage-1"])
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Riverside loop"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["routeStop-0"].firstMatch.label.contains("Austin, TX"))
        XCTAssertTrue(app.descendants(matching: .any)["routeStop-4"].firstMatch.label.contains("Austin, TX"))
        XCTAssertFalse(app.staticTexts["Coffee stop"].exists)
        app.buttons["Done"].tap()
        app.buttons["routePage-0"].tap()
        waitSelected(app.buttons["routePage-0"])
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStyleOptionsApplyAndCancelPreserveChoices() throws {
        let app = launch(scenario: "ready")
        screenshot(app, name: "Ride styles home")
        app.buttons["rideStyle-city"].tap()
        app.buttons["rideOptions"].tap()
        XCTAssertTrue(app.navigationBars["Make it yours"].waitForExistence(timeout: 5))
        app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
        app.buttons["stopKind-coffee"].tap()
        setSwitch(app.switches["avoidHighways"], on: true)
        app.buttons["applyRideOptions"].tap()
        XCTAssertTrue(app.buttons["rideOptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rideOptions"].label.contains("coffee"))
        app.buttons["rideOptions"].tap()
        XCTAssertTrue(app.segmentedControls["ridePace"].buttons["Include a stop"].isSelected)
        XCTAssertEqual(app.switches["avoidHighways"].value as? String, "1")
        screenshot(app, name: "Ride options sheet")
        app.segmentedControls["ridePace"].buttons["Just drive"].tap()
        setSwitch(app.switches["avoidHighways"], on: false)
        app.buttons["cancelRideOptions"].tap()
        app.buttons["rideOptions"].tap()
        XCTAssertTrue(app.segmentedControls["ridePace"].buttons["Include a stop"].isSelected)
        XCTAssertEqual(app.switches["avoidHighways"].value as? String, "1")
        app.buttons["cancelRideOptions"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["routeCard-4"].exists)
        XCTAssertTrue(app.staticTexts["routeTarget"].label.contains("coffee"))
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["routeStop-4"].firstMatch.label.contains("Mozart"))
        XCTAssertTrue(app.descendants(matching: .any)["routeStop-5"].firstMatch.label.contains("Austin, TX"))
    }

    @MainActor
    func testFailureCanRetryAndSuccessfulAlternativeRemainsAvailable() throws {
        let app = launch(scenario: "retry")
        app.segmentedControls["rideLength"].buttons["30 min"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["routeError"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["viewRouteStops"].exists)
        app.buttons["routePage-1"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        app.buttons["routePage-0"].tap()
        XCTAssertTrue(app.buttons["retryRoute"].waitForExistence(timeout: 5))
        app.buttons["retryRoute"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
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
    func testSurpriseOffersThreeStyles() throws {
        let app = launch(scenario: "ready")
        app.buttons["rideStyle-surprise"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["routePage-2"].waitForExistence(timeout: 10))
        for index in 0..<3 {
            app.buttons["routePage-\(index)"].tap()
            XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        }
    }

    @MainActor
    func testLargeTextKeepsRouteAndOptionsActionsReachable() throws {
        let app = launch(scenario: "ready", largeText: true)
        scrollTo(app.buttons["rideOptions"], in: app)
        app.buttons["rideOptions"].tap()
        XCTAssertTrue(app.buttons["applyRideOptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["applyRideOptions"].isHittable)
        screenshot(app, name: "Large text ride options")
        app.buttons["applyRideOptions"].tap()
        scrollTo(app.buttons["findRide"], in: app)
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 10))
        let action = app.buttons["viewRouteStops"]
        for _ in 0..<8 {
            if action.isHittable, action.frame.maxY <= app.frame.maxY - 40 { break }
            app.scrollViews["routePanelScroll"].swipeUp()
        }
        XCTAssertTrue(action.isHittable)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY - 30)
        screenshot(app, name: "Large text route cards fixture")
        action.tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
    }

    /// Network smoke test: every catalog loop, followed by a real coffee-stop request.
    @MainActor
    func testLiveStyleChoicesAndCoffeeStop() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 15))
        for style in ["water", "hills", "city"] {
            app.buttons["rideStyle-\(style)"].tap()
            app.buttons["findRide"].tap()
            for index in 0..<2 {
                XCTAssertTrue(app.buttons["routePage-\(index)"].waitForExistence(timeout: 10))
                app.buttons["routePage-\(index)"].tap()
                XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 90), app.debugDescription)
                app.buttons["fitRoute"].tap()
                screenshot(app, name: "Live \(style) route choice \(index + 1)")
            }
            app.buttons["closeRoutePreview"].tap()
        }
        app.buttons["rideOptions"].tap()
        app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
        app.buttons["stopKind-coffee"].tap()
        setSwitch(app.switches["avoidHighways"], on: true)
        app.buttons["applyRideOptions"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 90), app.debugDescription)
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
        let coffee = app.descendants(matching: .any)["routeStop-4"].firstMatch
        XCTAssertTrue(coffee.label.contains("Mozart"), app.debugDescription)
    }

    @MainActor
    private func launch(scenario: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SCENIC_ROUTE_TEST_SCENARIO"] = scenario
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func waitSelected(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    private func setSwitch(_ element: XCUIElement, on: Bool) {
        let expected = on ? "1" : "0"
        if element.value as? String != expected {
            // SwiftUI exposes the whole Form row as the switch; tap its trailing control.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
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
