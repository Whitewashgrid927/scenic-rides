import MapKit
import XCTest
@testable import ScenicRides

@MainActor
final class RoutePlannerTests: XCTestCase {
    func testCatalogCandidatesCoverEverySelectedSceneryAndAreDeterministic() {
        for mask in 1..<16 {
            let scenery = Set(Scenery.allCases.enumerated().compactMap { mask & (1 << $0.offset) == 0 ? nil : $0.element })
            for duration in RideDuration.allCases {
                for pace in [RidePace.drive, .stop] {
                    let request = RideRequest(startingPlace: .austin, duration: duration, scenery: scenery, options: RideOptions(pace: pace))
                    let choices = AustinLoop.candidates(for: request)
                    XCTAssertFalse(choices.isEmpty)
                    XCTAssertLessThanOrEqual(choices.count, 24)
                    XCTAssertEqual(Set(choices).count, choices.count)
                    XCTAssertTrue(choices.allSatisfy { pace == .stop ? !$0.stopPlacements(for: request).isEmpty : scenery.isSubset(of: $0.scenery) })
                    XCTAssertEqual(choices, AustinLoop.candidates(for: request))
                }
            }
        }
        let short = AustinLoop.candidates(for: RideRequest(startingPlace: .austin, duration: .thirty))
        let long = AustinLoop.candidates(for: RideRequest(startingPlace: .austin, duration: .ninety))
        XCTAssertNotEqual(short.first, long.first)
        XCTAssertTrue(short.contains(.riverfront))
        XCTAssertTrue(long.prefix(5).contains(.riverfront), "A compact fallback must survive the shortlist.")
    }

    func testBundledCatalogHas24UniqueRoutesAndValidatedPublicStops() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AustinCatalog", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let catalog = try AustinCatalog.decode(data)
        XCTAssertEqual(catalog.routes.count, 24)
        XCTAssertEqual(catalog.stops.count, 15)
        for kind in RideStopKind.allCases {
            XCTAssertGreaterThanOrEqual(catalog.stops.filter { $0.kinds.contains(kind) }.count, 4)
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        routes[1]["id"] = routes[0]["id"]; json["routes"] = routes
        XCTAssertThrowsError(try AustinCatalog.decode(JSONSerialization.data(withJSONObject: json)))
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        routes[0]["anchorIDs"] = ["not-in-catalog"]; json["routes"] = routes
        XCTAssertThrowsError(try AustinCatalog.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testNearbyStopsChooseDifferentPlacesAndAnInsertionAlongTheLoop() {
        let request = RideRequest(startingPlace: .austin, duration: .sixty, scenery: [.city], options: RideOptions(pace: .stop, stopKind: .coffee))
        let east = AustinLoop.allCases.first { $0.id == 15 }!
        let south = AustinLoop.allCases.first { $0.id == 20 }!
        XCTAssertEqual(east.stopPlacements(for: request).first?.stop.id, "cherrywood-coffee")
        XCTAssertEqual(south.stopPlacements(for: request).first?.stop.id, "radio")
        for loop in AustinLoop.allCases {
            for placement in loop.stopPlacements(for: request) {
                XCTAssertTrue(placement.stop.kinds.contains(.coffee))
                XCTAssertLessThanOrEqual(placement.addedDistance, 5_000)
                XCTAssertTrue(loop.anchors.contains { NearbyStops.distance($0.coordinate, placement.stop.anchor.coordinate) <= 3_000 })
                XCTAssertTrue((1...loop.anchors.count + 1).contains(placement.index))
            }
        }
        let stop = AustinCatalog.shared.stops.first { $0.id == "cherrywood-coffee" }!
        let points = [request.startingPlace.coordinate, stop.anchor.coordinate, CLLocationCoordinate2D(latitude: 30.32, longitude: -97.69), request.startingPlace.coordinate]
        let placement = NearbyStops.placements(for: request, loop: east, points: points, stops: [stop]).first!
        XCTAssertLessThan(placement.index, points.count - 1, "A stop already at an early waypoint should not be appended after the whole drive.")
        let north = StartingPlace(name: "Walnut Creek area", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.4, longitude: -97.7))
        let northRequest = RideRequest(startingPlace: north, duration: .thirty, scenery: [.greenery])
        XCTAssertNotEqual(AustinLoop.candidates(for: northRequest).first, AustinLoop.candidates(for: RideRequest(startingPlace: .austin, duration: .thirty, scenery: [.greenery])).first)
    }

    func testAIRankingSelectsANearbyStopButCannotOverrideTheTimeBudget() async throws {
        let loop = AustinLoop.allCases.first { $0.id == 13 }!
        let request = RideRequest(startingPlace: .austin, duration: .thirty, scenery: [.greenery, .city], options: RideOptions(pace: .stop, stopKind: .coffee, stopDuration: .twenty))
        let ranker = ReverseStopRanker()
        let planner = MapKitRoutePlanner(maps: TestMaps(), stopRanker: ranker)
        let route = try await planner.plan(request, loop: loop)
        XCTAssertEqual(route.stop?.id, loop.stopPlacements(for: request).last?.stop.id)
        XCTAssertEqual(route.stopSelection, .onDeviceAI)
        XCTAssertEqual(route.totalTime, 2_700)
        XCTAssertFalse(route.fits(request), "An AI preference cannot waive driving or stop time.")
        _ = try await planner.plan(request, loop: loop)
        XCTAssertEqual(ranker.calls, 1, "Successful rankings are reused within this immutable request.")
        _ = try await planner.plan(RideRequest(startingPlace: .austin, duration: .sixty, scenery: [.greenery, .city], options: request.options), loop: loop)
        XCTAssertEqual(ranker.calls, 2, "A new request gets a fresh ranking.")
    }

    func testCancelledMoreBatchLeavesExistingCardsAndCanResume() async {
        let choices = AustinLoop.allCases.filter { $0.scenery.contains(.greenery) }.prefix(6)
        let planner = DeferredPlanner(); let model = RoutePreviewModel(planner: planner)
        let request = RideRequest(startingPlace: .austin, duration: .sixty, scenery: [.greenery])
        let initial = Task { await model.loadChoices(request, loops: Array(choices)) }
        for choice in choices.prefix(5) { await planner.waitForRequest(choice); planner.finish(choice) }
        await initial.value
        let original = model.routes.map(\.id)
        // Leave the existing cards intact while the next route is pending.
        let last = choices.last!
        let more = Task { await model.loadMore() }
        await planner.waitForRequest(last)
        await model.loadMore() // A second tap while loading must not launch another request.
        more.cancel(); planner.finish(last); await more.value
        XCTAssertEqual(model.routes.map(\.id), original)
        XCTAssertNil(model.route(for: last)); XCTAssertTrue(model.canLoadMore)
        let resumed = Task { await model.loadMore() }
        await planner.waitForRequest(last); planner.finish(last); await resumed.value
        XCTAssertEqual(Array(model.routes.prefix(original.count)).map(\.id), original)
        XCTAssertNotNil(model.route(for: last))
    }

    func testMoreRoutesUsesBoundedBatchesKeepsCardsAndRevealsCachedMatches() async {
        let planner = FixedPlanner(times: [:]); let model = RoutePreviewModel(planner: planner)
        let request = RideRequest(startingPlace: .austin, duration: .sixty, scenery: [.greenery])
        let choices = AustinLoop.candidates(for: request)
        await model.loadChoices(request)
        XCTAssertEqual(planner.calls.count, 5); XCTAssertEqual(model.routes.count, 3)
        let originalIDs = model.routes.map(\.id)
        await model.loadMore()
        XCTAssertEqual(planner.calls.count, 10); XCTAssertEqual(model.routes.count, 6)
        XCTAssertEqual(Array(model.routes.prefix(3)).map(\.id), originalIDs)
        await model.loadMore()
        XCTAssertEqual(planner.calls.count, 10, "Already checked matches do not need more directions.")
        XCTAssertEqual(model.routes.count, 9)
        while model.canLoadMore { await model.loadMore() }
        XCTAssertEqual(Set(planner.calls), Set(choices))
        XCTAssertEqual(planner.calls.count, choices.count)
        XCTAssertEqual(Set(model.routes.map(\.loop)).count, model.routes.count)
        let count = planner.calls.count
        await model.loadMore(); XCTAssertEqual(planner.calls.count, count)
    }

    func testOverBudgetLaterBatchDoesNotReplaceExistingRoutes() async {
        let request = RideRequest(startingPlace: .austin, duration: .thirty, scenery: [.greenery])
        let choices = AustinLoop.candidates(for: request)
        let planner = FixedPlanner(times: Dictionary(uniqueKeysWithValues: choices.enumerated().map { ($0.element, $0.offset < 3 ? 600.0 : 7_200.0) }))
        let model = RoutePreviewModel(planner: planner)
        await model.loadChoices(request)
        let ids = model.routes.map(\.id)
        await model.loadMore()
        XCTAssertEqual(model.routes.map(\.id), ids)
        XCTAssertEqual(model.batchMessage, "No new routes fit this budget.")
        XCTAssertTrue(model.canLoadMore)
    }

    func testLaterBatchFailureRetriesOnlyFailuresAndRetainsEarlierMatches() async {
        let request = RideRequest(startingPlace: .austin, duration: .sixty, scenery: [.greenery])
        let choices = AustinLoop.candidates(for: request)
        let planner = FixedPlanner(times: [:]); planner.failOnce = [choices[5]]
        let model = RoutePreviewModel(planner: planner)
        await model.loadChoices(request)
        let ids = model.routes.map(\.id)
        await model.loadMore()
        XCTAssertTrue(model.hasFailures)
        let calls = planner.calls.count
        await model.loadChoices(request)
        XCTAssertEqual(planner.calls.count, calls + 1)
        XCTAssertEqual(planner.calls.last, choices[5])
        XCTAssertEqual(Array(model.routes.prefix(3)).map(\.id), ids)
        XCTAssertFalse(model.hasFailures)
    }

    func testNoFitCanSearchRemainingCatalogAndFindAMatch() async {
        let request = RideRequest(startingPlace: .austin, duration: .thirty, scenery: [.greenery])
        let choices = AustinLoop.candidates(for: request)
        let planner = FixedPlanner(times: Dictionary(uniqueKeysWithValues: choices.enumerated().map { ($0.element, $0.offset < 5 ? 3_600.0 : 600.0) }))
        let model = RoutePreviewModel(planner: planner)
        await model.loadChoices(request)
        XCTAssertTrue(model.routes.isEmpty); XCTAssertTrue(model.canLoadMore)
        await model.loadMore()
        XCTAssertEqual(model.routes.count, 3)
        XCTAssertTrue(model.routes.allSatisfy { $0.fits(request) })
    }

    func testEveryLoopReturnsToTheSelectedStartAndSumsEveryLeg() async throws {
        for loop in AustinLoop.allCases {
            let maps = TestMaps()
            let start = StartingPlace(name: "Public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.28, longitude: -97.76))
            let request = RideRequest(startingPlace: start, duration: .sixty)
            let route = try await MapKitRoutePlanner(maps: maps, stopRanker: DistanceStopRanker()).plan(request, loop: loop)
            let count = loop.anchors.count + 1
            XCTAssertEqual(maps.journeys.count, count)
            XCTAssertFalse(route.highlights.contains(where: \.isStop))
            XCTAssertEqual(maps.journeys.first?.0.coordinate.latitude, start.latitude)
            XCTAssertEqual(maps.journeys.last?.1.coordinate.latitude, start.latitude)
            XCTAssertEqual(maps.journeys.last?.1.coordinate.longitude, start.longitude)
            XCTAssertEqual(route.distance, Double(count) * 1_609.344, accuracy: 0.001)
            XCTAssertEqual(route.expectedTravelTime, Double(count) * 300)
            XCTAssertEqual(route.totalTime, route.expectedTravelTime)
            XCTAssertEqual(route.stopMinutes, 0)
            for index in 1..<maps.departures.count {
                XCTAssertEqual(maps.departures[index].timeIntervalSince(maps.departures[index - 1]), 300)
            }
            for waypoint in route.waypoints { XCTAssertTrue(route.mapRect.contains(MKMapPoint(waypoint.coordinate))) }
        }
    }

    func testStopTimeCountsTowardBudgetAndDelaysReturnDeparture() async throws {
        for loop in AustinLoop.allCases {
            for kind in RideStopKind.allCases {
                let maps = TestMaps()
                let options = RideOptions(pace: .stop, stopKind: kind, stopDuration: .twenty, roads: RoadPreferences(avoidHighways: true, avoidTolls: false))
                let request = RideRequest(startingPlace: .austin, duration: .sixty, options: options, departure: Date(timeIntervalSince1970: 1_800_000_000))
                if loop.stopPlacements(for: request).isEmpty {
                    do {
                        _ = try await MapKitRoutePlanner(maps: maps, stopRanker: DistanceStopRanker()).plan(request, loop: loop)
                        XCTFail("A distant stop must not be substituted.")
                    } catch { XCTAssertEqual(error as? RoutePlanningError, .noNearbyStop) }
                    continue
                }
                let route = try await MapKitRoutePlanner(maps: maps, stopRanker: DistanceStopRanker()).plan(request, loop: loop)
                let legCount = loop.anchors.count + 2
                XCTAssertEqual(route.highlights.filter(\.isStop).count, 1)
                XCTAssertEqual(route.legs.count, legCount)
                XCTAssertEqual(route.totalTime, Double(legCount) * 300 + 1_200)
                XCTAssertEqual(route.options, options)
                XCTAssertEqual(maps.roadPreferences, Array(repeating: options.roads, count: legCount))
                XCTAssertEqual(maps.departures.last?.timeIntervalSince(request.departure), Double(legCount - 1) * 300 + 1_200)
                XCTAssertEqual(route.waypoints.last?.coordinate.longitude, request.startingPlace.longitude)
            }
        }
    }

    func testFitUsesExactTotalAndAllSceneryThenRanksClosestToBudget() async {
        let planner = FixedPlanner(times: [.parks: 1_200, .hills: 2_700.01, .lake: 2_700, .riverAndHills: 2_400])
        let model = RoutePreviewModel(planner: planner)
        let request = RideRequest(startingPlace: .austin, duration: .sixty, scenery: [.water, .hills], options: RideOptions(pace: .stop, stopKind: .coffee))
        await model.loadChoices(request, loops: [.parks, .hills, .lake, .riverAndHills])
        XCTAssertEqual(model.routes.map(\.loop), [.lake, .riverAndHills])
        XCTAssertEqual(model.routes.first?.minutes, 60)
        XCTAssertEqual(model.routes.first?.stopMinutes, 15)
        XCTAssertTrue(model.routes.allSatisfy { $0.totalTime <= 3_600 })
        XCTAssertFalse(model.routes.contains { $0.loop == .parks }, "A short route missing Hills is not a match.")
        XCTAssertFalse(model.routes.contains { $0.loop == .hills }, "Even a fraction of a second over budget is excluded.")
    }

    func testIncreasingStopTimeCanRemoveARouteWithoutDroppingTheStop() async {
        let planner = FixedPlanner(times: [.hills: 2_700])
        let model = RoutePreviewModel(planner: planner)
        let shorter = RideRequest(startingPlace: .austin, duration: .sixty, options: RideOptions(pace: .stop, stopDuration: .fifteen))
        await model.loadChoices(shorter, loops: [.hills])
        XCTAssertEqual(model.routes.first?.minutes, 60)
        let longer = RideRequest(startingPlace: .austin, duration: .sixty, options: RideOptions(pace: .stop, stopDuration: .twenty))
        await model.loadChoices(longer, loops: [.hills])
        XCTAssertTrue(model.routes.isEmpty)
        XCTAssertEqual(model.shortestMinutes, 65)
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.route(for: .hills)?.stopMinutes, 20)
    }

    func testNoFitUsesActualEstimatesAndDoesNotPretendToFillTheBudget() async {
        let model = RoutePreviewModel(planner: FixedPlanner(times: [.parks: 2_400, .riverside: 2_100]))
        let request = RideRequest(startingPlace: .austin, duration: .thirty)
        await model.loadChoices(request, loops: [.parks, .riverside])
        XCTAssertTrue(model.routes.isEmpty)
        XCTAssertEqual(model.shortestMinutes, 35)
        XCTAssertNil(model.failure)
    }

    func testPreflightRejectsImpossibleStopEmptySceneryAndUnsupportedStart() async {
        let planner = FixedPlanner(times: [:])
        let model = RoutePreviewModel(planner: planner)
        await model.loadChoices(RideRequest(startingPlace: .austin, duration: .thirty, options: RideOptions(pace: .stop, stopDuration: .thirty)))
        XCTAssertEqual(model.failure, .stopExceedsBudget)
        await model.loadChoices(RideRequest(startingPlace: .austin, duration: .sixty, scenery: []))
        XCTAssertEqual(model.failure, .invalidPreferences)
        let outside = StartingPlace(name: "Outside Austin", detail: "", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060))
        await model.loadChoices(RideRequest(startingPlace: outside, duration: .sixty))
        XCTAssertEqual(model.failure, .outsideAustin)
        XCTAssertTrue(planner.calls.isEmpty)
    }

    func testRetryPreservesCompleteAlternativesAndNewRequestClearsCache() async {
        let planner = FixedPlanner(times: [.parks: 1_200, .riverside: 1_500, .hills: 5_000])
        planner.failOnce = [.parks]
        let model = RoutePreviewModel(planner: planner)
        let request = RideRequest(startingPlace: .austin, duration: .sixty)
        await model.loadChoices(request, loops: [.parks, .riverside, .hills])
        let cachedID = model.route(for: .riverside)?.id
        XCTAssertEqual(model.routes.map(\.loop), [.riverside])
        XCTAssertTrue(model.hasFailures)
        await model.loadChoices(request, loops: [.parks, .riverside, .hills])
        XCTAssertEqual(planner.calls, [.parks, .riverside, .hills, .parks])
        XCTAssertEqual(model.route(for: .riverside)?.id, cachedID)
        XCTAssertFalse(model.hasFailures)
        let newStart = StartingPlace(name: "Another public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.28, longitude: -97.75))
        await model.loadChoices(RideRequest(startingPlace: newStart, duration: .sixty), loops: [.parks])
        XCTAssertNil(model.route(for: .riverside))
        XCTAssertEqual(model.route(for: .parks)?.waypoints.first?.coordinate.latitude, newStart.latitude)
    }

    func testFailedReturnLegCannotPublishPartialRoundTripAndRetryRecovers() async {
        let maps = TestMaps()
        maps.failAtLeg = 4
        let model = RoutePreviewModel(planner: MapKitRoutePlanner(maps: maps, stopRanker: DistanceStopRanker()))
        let request = RideRequest(startingPlace: .austin, duration: .sixty)
        await model.loadChoices(request, loops: [.hills])
        XCTAssertTrue(model.routes.isEmpty)
        XCTAssertEqual(model.failure, .unavailable)
        maps.failAtLeg = nil
        await model.loadChoices(request, loops: [.hills])
        XCTAssertEqual(model.routes.first?.legs.count, 4)
    }

    func testStartingAtAHighlightSkipsZeroLengthLeg() async throws {
        let maps = TestMaps()
        let start = StartingPlace(name: "Public starting point", detail: "Austin", coordinate: AustinLoop.parks.anchors[0].coordinate)
        let route = try await MapKitRoutePlanner(maps: maps, stopRanker: DistanceStopRanker()).plan(RideRequest(startingPlace: start, duration: .thirty), loop: .parks)
        XCTAssertEqual(maps.journeys.count, 3)
        XCTAssertEqual(route.legs.count, 4)
        XCTAssertEqual(route.legs.first?.expectedTravelTime, 0)
        XCTAssertEqual(route.totalTime, 900)
    }

    func testMapKitReceivesRoadPreferencesAndStopAdjustedDeparture() {
        let point = RouteWaypoint(id: "start", name: "Austin", detail: "", coordinate: StartingPlace.austin.coordinate)
        let afterStop = Date(timeIntervalSince1970: 1_800_001_200)
        for avoid in [true, false] {
            let request = AppleRouteMapService.directionsRequest(from: point, to: point, departure: afterStop, preferences: RoadPreferences(avoidHighways: avoid, avoidTolls: !avoid))
            XCTAssertEqual(request.highwayPreference, avoid ? .avoid : .any)
            XCTAssertEqual(request.tollPreference, avoid ? .any : .avoid)
            XCTAssertEqual(request.transportType, .automobile)
            XCTAssertEqual(request.departureDate, afterStop)
        }
    }

    func testOlderRequestCannotRestoreOldRoutesOrBudget() async {
        let planner = DeferredPlanner()
        let model = RoutePreviewModel(planner: planner)
        let first = Task { await model.loadChoices(RideRequest(startingPlace: .austin, duration: .ninety), loops: [.hills]) }
        await planner.waitForRequest(.hills)
        let second = Task { await model.loadChoices(RideRequest(startingPlace: .austin, duration: .thirty), loops: [.lake]) }
        await planner.waitForRequest(.lake)
        planner.finish(.lake)
        await second.value
        planner.finish(.hills)
        await first.value
        XCTAssertEqual(model.routes.map(\.loop), [.lake])
        XCTAssertNil(model.route(for: .hills))
        XCTAssertFalse(model.isLoading)
    }

    func testCancelledResponseIsDiscarded() async {
        let planner = DeferredPlanner()
        let model = RoutePreviewModel(planner: planner)
        let task = Task { await model.loadChoices(RideRequest(startingPlace: .austin, duration: .sixty), loops: [.hills]) }
        await planner.waitForRequest(.hills)
        task.cancel()
        planner.finish(.hills)
        await task.value
        XCTAssertTrue(model.routes.isEmpty)
        XCTAssertNil(model.route(for: .hills))
    }
}

@MainActor
private final class TestMaps: RouteMapServing {
    var resolutions = 0
    var journeys: [(RouteWaypoint, RouteWaypoint)] = []
    var departures: [Date] = []
    var failAtLeg: Int?
    var roadPreferences: [RoadPreferences] = []

    func resolve(_ anchor: RouteAnchor) async throws -> RouteWaypoint {
        resolutions += 1
        return RouteWaypoint(id: anchor.id, name: anchor.name, detail: anchor.address,
                             coordinate: anchor.coordinate, isStop: anchor.isStop, scenery: anchor.scenery)
    }

    func directions(from: RouteWaypoint, to: RouteWaypoint, departure: Date, preferences: RoadPreferences) async throws -> RouteLeg {
        roadPreferences.append(preferences)
        journeys.append((from, to)); departures.append(departure)
        if journeys.count == failAtLeg { throw RoutePlanningError.unavailable }
        let coordinates = [from.coordinate, to.coordinate]
        return RouteLeg(polyline: MKPolyline(coordinates: coordinates, count: 2), distance: 1_609.344, expectedTravelTime: 300)
    }
}

@MainActor
private func fixture(_ request: RideRequest, loop: AustinLoop, seconds: TimeInterval) -> ScenicRoute {
    let start = request.startingPlace
    var points = [RouteWaypoint(id: "start", name: start.name, detail: "", coordinate: start.coordinate),
                  RouteWaypoint(id: "return", name: start.name, detail: "", coordinate: start.coordinate)]
    if request.options.pace == .stop {
        let stop = loop.stopPlacements(for: request).first?.stop ?? AustinCatalog.shared.stops.first { $0.kinds.contains(request.options.stopKind) }!
        points.insert(RouteWaypoint(id: stop.id, name: stop.name, detail: stop.address, coordinate: stop.anchor.coordinate, isStop: true, scenery: stop.scenery), at: 1)
    }
    let coords = points.map(\.coordinate)
    return ScenicRoute(loop: loop, waypoints: points,
                       legs: [RouteLeg(polyline: MKPolyline(coordinates: coords, count: 2), distance: 1_000, expectedTravelTime: seconds)], options: request.options)
}

@MainActor
private final class FixedPlanner: RoutePlanning {
    let times: [AustinLoop: TimeInterval]
    var calls: [AustinLoop] = []
    var failOnce: Set<AustinLoop> = []
    init(times: [AustinLoop: TimeInterval]) { self.times = times }
    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        calls.append(loop)
        if failOnce.remove(loop) != nil { throw RoutePlanningError.unavailable }
        return fixture(request, loop: loop, seconds: times[loop] ?? 600)
    }
}

@MainActor
private final class DeferredPlanner: RoutePlanning {
    private var pending: [AustinLoop: CheckedContinuation<Void, Never>] = [:]
    private var observers: [AustinLoop: CheckedContinuation<Void, Never>] = [:]

    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        await withCheckedContinuation { continuation in
            pending[loop] = continuation
            observers.removeValue(forKey: loop)?.resume()
        }
        return fixture(request, loop: loop, seconds: 600)
    }
    func waitForRequest(_ loop: AustinLoop) async {
        if pending[loop] != nil { return }
        await withCheckedContinuation { observers[loop] = $0 }
    }
    func finish(_ loop: AustinLoop) {
        pending.removeValue(forKey: loop)?.resume()
    }
}

private extension AustinLoop {
    static var parks: Self { allCases.first { $0.id == 0 }! }
    static var riverside: Self { allCases.first { $0.id == 1 }! }
    static var hills: Self { allCases.first { $0.id == 2 }! }
    static var lake: Self { allCases.first { $0.id == 3 }! }
    static var riverAndHills: Self { allCases.first { $0.id == 6 }! }
    static var riverfront: Self { allCases.first { $0.id == 10 }! }
}

@MainActor
private struct DistanceStopRanker: StopRanking {
    func rank(_ candidates: [StopPlacement], request: RideRequest, loop: AustinLoop) async throws -> RankedStops {
        RankedStops(placements: candidates, method: .nearby(.unavailable))
    }
}

@MainActor
private final class ReverseStopRanker: StopRanking {
    var calls = 0
    func rank(_ candidates: [StopPlacement], request: RideRequest, loop: AustinLoop) async throws -> RankedStops {
        calls += 1
        return RankedStops(placements: Array(candidates.reversed()), method: .onDeviceAI)
    }
}
