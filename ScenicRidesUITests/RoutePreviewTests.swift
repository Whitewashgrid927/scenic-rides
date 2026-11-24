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
        XCTAssertTrue(selectedCard(in: app).label.contains("Water · Hills"))
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
        XCTAssertTrue(app.staticTexts["routePosition"].label.contains("1 of"))
        app.scrollViews["routeCards"].swipeLeft()
        XCTAssertTrue(app.staticTexts["routePosition"].label.contains("2 of"))
        let name = app.otherElements["routeMap"].value as? String ?? ""
        XCTAssertFalse(name.isEmpty)
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.navigationBars["Your route"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[name].exists)
        let start = app.descendants(matching: .any)["routeStop-0"].firstMatch
        XCTAssertTrue(start.label.contains("Austin, TX"))
        let end = app.descendants(matching: .any)["routeStop-return"].firstMatch
        scrollTo(end, in: app)
        XCTAssertTrue(end.label.contains("Austin, TX"))
        XCTAssertFalse(app.descendants(matching: .any)["routeStop-optional"].firstMatch.exists)
        app.buttons["Done"].tap()
        app.buttons["previousRoute"].tap()
        XCTAssertTrue(app.staticTexts["routePosition"].label.contains("1 of"))
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
        XCTAssertTrue(selectedCard(in: app).label.contains("20 min stop"))
        let total = selectedTotal(in: app)
        XCTAssertTrue(app.staticTexts["routeTarget"].label.contains("60 min budget"))
        app.buttons["viewRouteStops"].tap()
        XCTAssertTrue(app.staticTexts["Whole trip"].waitForExistence(timeout: 5))
        // Native LabeledContent exposes each row as a combined accessibility label.
        XCTAssertTrue(app.staticTexts["Time at stop, 20 min"].exists)
        XCTAssertTrue(app.staticTexts["Whole trip, About \(total) min"].exists)
        XCTAssertTrue(app.staticTexts["Your budget, 60 min"].exists)
        let stop = app.descendants(matching: .any)["routeStop-optional"].firstMatch
        scrollTo(stop, in: app)
        XCTAssertTrue(stop.label.contains("20 min stop"))
        XCTAssertTrue(["Mozart", "Epoch", "Cherrywood", "Radio"].contains { stop.label.contains($0) })
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
        let selectedID = selectedCard(in: partial).identifier
        partial.buttons["retryRoute"].tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: partial.buttons["retryRoute"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertTrue(partial.buttons[selectedID].isSelected)
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

    @MainActor
    func testMoreRoutesPreservesSelectionAndEventuallyFinishes() throws {
        let app = launch()
        app.buttons["scenery-water"].tap(); app.buttons["scenery-greenery"].tap()
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        let original = selectedCard(in: app).identifier
        XCTAssertEqual(routeCount(in: app), 3)
        app.buttons["moreRoutes"].tap()
        waitForMore(in: app)
        XCTAssertGreaterThan(routeCount(in: app), 3)
        XCTAssertTrue(app.buttons[original].isSelected)
        screenshot(app, name: "More routes fixture")
        for _ in 0..<12 {
            if !app.buttons["moreRoutes"].exists { break }
            app.buttons["moreRoutes"].tap(); waitForMore(in: app)
        }
        XCTAssertFalse(app.buttons["moreRoutes"].exists)
        XCTAssertTrue(app.staticTexts["routesExhausted"].exists)
        XCTAssertTrue(app.buttons[original].isSelected)
        app.buttons["nextRoute"].tap()
        XCTAssertTrue(app.staticTexts["routePosition"].label.contains("2 of"))
    }

    @MainActor
    func testMoreRoutesFailureCanRetryWithoutLosingSelection() throws {
        let app = launch(scenario: "moreRetry")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        let original = selectedCard(in: app).identifier
        app.buttons["moreRoutes"].tap(); waitForMore(in: app)
        XCTAssertTrue(app.buttons["retryRoute"].exists)
        app.buttons["retryRoute"].tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["retryRoute"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertTrue(app.buttons[original].isSelected)
    }

    @MainActor
    func testLoadingMoreKeepsCurrentRouteAndCanBeDismissed() throws {
        let app = launch(scenario: "loadingMore")
        app.buttons["findRide"].tap()
        XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
        let original = selectedCard(in: app).identifier
        app.buttons["moreRoutes"].tap()
        XCTAssertTrue(app.buttons[original].isSelected)
        XCTAssertFalse(app.buttons["moreRoutes"].isEnabled)
        XCTAssertTrue(app.buttons["viewRouteStops"].isEnabled)
        app.buttons["closeRoutePreview"].tap()
        XCTAssertTrue(app.buttons["findRide"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAIAndFallbackAreClearlyDistinguished() throws {
        for scenario in ["aiReady", "ready"] {
            let app = launch(scenario: scenario)
            app.buttons["rideOptions"].tap()
            app.segmentedControls["ridePace"].buttons["Include a stop"].tap()
            app.buttons["applyRideOptions"].tap()
            app.buttons["findRide"].tap()
            XCTAssertTrue(app.buttons["viewRouteStops"].waitForExistence(timeout: 15))
            let expected = scenario == "aiReady" ? "Picked with on-device AI" : "Nearby match · AI unavailable"
            XCTAssertTrue(selectedCard(in: app).label.contains(expected))
            app.buttons["viewRouteStops"].tap()
            XCTAssertEqual(app.staticTexts["stopSelectionMethod"].label, expected)
            app.terminate()
        }
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
            if budget == 30 {
                let original = selectedCard(in: app).identifier
                let originalCount = routeCount(in: app)
                XCTAssertTrue(app.buttons["moreRoutes"].exists)
                app.buttons["moreRoutes"].tap()
                XCTAssertTrue(app.staticTexts["moreRoutesMessage"].waitForExistence(timeout: 120))
                XCTAssertTrue(app.buttons[original].isSelected)
                XCTAssertGreaterThanOrEqual(routeCount(in: app), originalCount)
                for total in app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routeTotal-")).allElementsBoundByIndex {
                    let minutes = total.label.split(separator: " ").compactMap { Int($0) }.first
                    XCTAssertLessThanOrEqual(minutes ?? 999, budget)
                }
                screenshot(app, name: "Live more routes")
            }
            if budget > 30 {
                app.buttons["viewRouteStops"].tap()
                let stop = app.descendants(matching: .any)["routeStop-optional"].firstMatch
                scrollTo(stop, in: app)
                XCTAssertFalse(stop.label.isEmpty)
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
    private func selectedCard(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "routeCard-")).firstMatch
    }
    @MainActor
    private func selectedTotal(in app: XCUIApplication) -> Int {
        let label = selectedCard(in: app).staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routeTotal-")).firstMatch.label
        return label.split(separator: " ").compactMap { Int($0) }.first ?? -1
    }
    @MainActor
    private func routeCount(in app: XCUIApplication) -> Int {
        app.staticTexts["routePosition"].label.split(separator: " ").compactMap { Int($0) }.last ?? 0
    }
    @MainActor
    private func waitForMore(in app: XCUIApplication) {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.staticTexts["moreRoutesMessage"])
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 15), .completed)
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
