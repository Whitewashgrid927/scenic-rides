import XCTest

final class RoutePreviewTests: XCTestCase {
    @MainActor
    func testMultipleSceneryChoicesAndEmptySelectionGuard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["scenery-water"].isSelected)
        app.buttons["scenery-hills"].tap()
        XCTAssertTrue(app.buttons["scenery-water"].isSelected)
        XCTAssertTrue(app.buttons["scenery-hills"].isSelected)
        screenshot(app, name: "Multiple scenery home")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["routeCard-7"].label.contains("Water · Hills"))
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(app.buttons["scenery-hills"].isSelected)
        app.buttons["scenery-water"].tap()
        XCTAssertFalse(app.buttons["scenery-water"].isSelected)
        XCTAssertTrue(app.buttons["scenery-hills"].isSelected)
        app.buttons["scenery-hills"].tap()
        XCTAssertFalse(app.buttons["findRide"].isEnabled)
        XCTAssertTrue(app.staticTexts["Choose at least one kind of scenery."].exists)
        app.buttons["scenery-greenery"].tap()
        XCTAssertTrue(app.buttons["findRide"].isEnabled)
    }

    @MainActor
    func testSwipeChangesSelectedRouteAndItsItinerary() throws {
        let app = launch()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["routePage-0"].isSelected)
        app.scrollViews["routeCards"].swipeLeft()
        waitSelected(app.buttons["routePage-1"])
        XCTAssertTrue(app.buttons["routeCard-6"].isSelected)
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["River, hills & skyline"].exists)
        let start = app.descendants(matching: .any)["routeStop-0"].firstMatch
        XCTAssertTrue(start.label.contains("Austin, TX"))
        let end = app.descendants(matching: .any)["routeStop-return"].firstMatch
        scrollTo(end, in: app)
        XCTAssertTrue(end.label.contains("Austin, TX"))
        XCTAssertFalse(app.descendants(matching: .any)["routeStop-optional"].firstMatch.exists)
        app.buttons["Done"].tap()
        app.buttons["routePage-0"].tap()
        waitSelected(app.buttons["routePage-0"])
    }

    @MainActor
    func testStopTimeApplyCancelAndBudgetBreakdown() throws {
        let app = launch()
        app.buttons["scenery-hills"].tap()
        app.buttons["rideOptions"].tap()
        app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
        app.buttons["stopKind-coffee"].tap()
        setStopTime(20, in: app)
        setSwitch(app.switches["avoidHighways"], on: true)
        screenshot(app, name: "Stop time options")
        app.buttons["applyRideOptions"].tap()
        XCTAssertTrue(app.buttons["rideOptions"].label.contains("20 min"))
        app.buttons["rideOptions"].tap()
        XCTAssertTrue(app.segmentedControls["ridePace"].buttons["Include a stop"].isSelected)
        setStopTime(30, in: app)
        setSwitch(app.switches["avoidHighways"], on: false)
        app.buttons["cancelRideOptions"].tap()
        app.buttons["rideOptions"].tap()
        XCTAssertEqual(app.switches["avoidHighways"].value as? String, "1")
        let savedTime = app.descendants(matching: .any)["stopTime"].firstMatch
        XCTAssertTrue("\(savedTime.label) \(savedTime.value as? String ?? "")".contains("20 min"))
        app.buttons["cancelRideOptions"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["routeCard-2"].label.contains("20 min stop"))
        XCTAssertTrue(app.staticTexts["routeTarget"].label.contains("60 min budget"))
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.staticTexts["Whole trip"].waitForExistence(timeout: 5))
        // Native LabeledContent exposes each row as a combined accessibility label.
        XCTAssertTrue(app.staticTexts["Time at stop, 20 min"].exists)
        XCTAssertTrue(app.staticTexts["Whole trip, About 54 min"].exists)
        XCTAssertTrue(app.staticTexts["Your budget, 60 min"].exists)
        let stop = app.descendants(matching: .any)["routeStop-optional"].firstMatch
        scrollTo(stop, in: app)
        XCTAssertTrue(stop.label.contains("20 min stop"))
        XCTAssertTrue(stop.label.contains("Mozart"))
    }

    @MainActor
    func testNoFitNeverShowsAnOverBudgetRecommendation() throws {
        let app = launch(scenario: "overBudget")
        app.segmentedControls["rideLength"].buttons["30 min"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["routeError"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["routeEmptyMessage"].label.contains("35 minutes"))
        XCTAssertFalse(app.buttons["viewRouteStops"].exists)
        XCTAssertFalse(app.scrollViews["routeCards"].exists)
        screenshot(app, name: "No budget fit fixture")
        app.buttons["adjustRide"].tap()
        XCTAssertTrue(app.segmentedControls["rideLength"].buttons["30 min"].isSelected)
        XCTAssertTrue(app.buttons["scenery-water"].isSelected)
    }

    @MainActor
    func testStopCannotConsumeWholeBudget() throws {
        let app = launch()
        app.segmentedControls["rideLength"].buttons["30 min"].tap()
        app.buttons["rideOptions"].tap()
        app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
        setStopTime(30, in: app)
        app.buttons["applyRideOptions"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["Leave some time for the drive"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["viewRouteStops"].exists)
        app.buttons["adjustRide"].tap()
        XCTAssertTrue(app.buttons["rideOptions"].label.contains("30 min"))
    }

    @MainActor
    func testFailureRetryAndPartialAlternativePreserveSelection() throws {
        let app = launch(scenario: "retry")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["Routes couldn’t load"].waitForExistence(timeout: 15))
        app.buttons["retryRoute"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        app.terminate()
        let partial = launch(scenario: "partial")
        partial.buttons["findRide"].tap()
        XCTAssertTrue(partial.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        XCTAssertTrue(partial.buttons["routeCard-6"].isSelected)
        partial.buttons["retryRoute"].tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: partial.buttons["retryRoute"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertTrue(partial.buttons["routeCard-6"].isSelected)
        XCTAssertTrue(partial.buttons["routePage-1"].isSelected)
    }

    @MainActor
    func testLoadingCanBeDismissed() throws {
        let app = launch(scenario: "loading")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.staticTexts["Checking scenery, stops and the way back…"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["viewRouteStops"].exists)
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeTextKeepsOptionsAndItineraryActionsReachable() throws {
        let app = launch(largeText: true)
        scrollTo(app.buttons["rideOptions"], in: app)
        app.buttons["rideOptions"].tap()
        app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
        XCTAssertTrue(app.buttons["applyRideOptions"].isHittable)
        screenshot(app, name: "Large text stop options")
        app.buttons["applyRideOptions"].tap()
        scrollTo(app.buttons["findRide"], in: app)
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        let action = app.buttons["viewRouteStops"]
        for _ in 0..<10 {
            if action.isHittable, action.frame.maxY <= app.frame.maxY - 40 { break }
            app.scrollViews["routePanelScroll"].swipeUp()
        }
        XCTAssertTrue(action.isHittable)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY - 30)
        screenshot(app, name: "Large text total budget fixture")
        action.tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
    }

    /// Real MapKit: short drive, mixed scenery with coffee, then a longer outing with a walk.
    @MainActor
    func testLiveBudgetsAndMixedSceneryWithStops() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 15))
        for budget in [30, 60, 90] {
            app.segmentedControls["rideLength"].buttons["\(budget) min"].tap()
            if budget == 60 { app.buttons["scenery-hills"].tap() }
            if budget == 90 {
                app.buttons["scenery-greenery"].tap()
                app.buttons["scenery-city"].tap()
            }
            if budget > 30 {
                app.buttons["rideOptions"].tap()
                app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
                app.buttons[budget == 60 ? "stopKind-coffee" : "stopKind-walk"].tap()
                setStopTime(budget == 60 ? 15 : 20, in: app)
                app.buttons["applyRideOptions"].tap()
            }
            app.buttons["findRide"].tap()
            XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 120), app.debugDescription)
            let totals = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routeTotal-"))
            XCTAssertGreaterThan(totals.count, 0)
            for total in totals.allElementsBoundByIndex {
                let number = total.label.split(separator: " ").compactMap { Int($0) }.first
                XCTAssertNotNil(number)
                XCTAssertLessThanOrEqual(number ?? 999, budget)
            }
            app.buttons["fitRoute"].tap()
            screenshot(app, name: "Live \(budget) minute budget")
            if budget > 30 {
                app.buttons["viewRouteStops"].tap()
                let stop = app.descendants(matching: .any)["routeStop-optional"].firstMatch
                scrollTo(stop, in: app)
                XCTAssertTrue(stop.label.contains(budget == 60 ? "Mozart" : "Butler Park"))
                XCTAssertTrue(stop.label.contains(budget == 60 ? "15 min stop" : "20 min stop"))
                let end = app.descendants(matching: .any)["routeStop-return"].firstMatch
                scrollTo(end, in: app)
                XCTAssertTrue(end.label.contains("Austin, TX"))
                screenshot(app, name: "Live \(budget) minute stop itinerary")
                app.buttons["Done"].tap()
            }
            app.buttons["closeRoutePreview"].tap()
        }
    }

    @MainActor
    private func launch(scenario: String = "ready", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SCENIC_ROUTE_TEST_SCENARIO"] = scenario
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func setStopTime(_ minutes: Int, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["stopTime"].firstMatch
        picker.tap()
        app.collectionViews.buttons["\(minutes) min"].tap()
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
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists, element.isHittable, element.frame.maxY <= app.frame.maxY - 40 { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
