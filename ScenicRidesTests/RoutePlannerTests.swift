import MapKit
import XCTest
@testable import ScenicRides

@MainActor
final class RoutePlannerTests: XCTestCase {
    func testShortlistCoversEverySelectedSceneryAndBoundsNetworkWork() {
        for mask in 1..<16 {
            let scenery = Set(Scenery.allCases.enumerated().compactMap { mask & (1 << $0.offset) == 0 ? nil : $0.element })
            for duration in RideDuration.allCases {
                for pace in [RidePace.drive, .stop] {
                    let request = RideRequest(startingPlace: .austin, duration: duration, scenery: scenery, options: RideOptions(pace: pace))
                    let choices = AustinLoop.candidates(for: request)
                    XCTAssertFalse(choices.isEmpty)
                    XCTAssertLessThanOrEqual(choices.count, 5)
                    XCTAssertEqual(Set(choices).count, choices.count)
                    XCTAssertTrue(choices.allSatisfy { scenery.isSubset(of: $0.scenery(options: request.options)) })
                    XCTAssertEqual(choices, AustinLoop.candidates(for: request))
                }
            }
        }
        let short = AustinLoop.candidates(for: RideRequest(startingPlace: .austin, duration: .thirty))
        let long = AustinLoop.candidates(for: RideRequest(startingPlace: .austin, duration: .ninety))
        XCTAssertNotEqual(short.first, long.first)
        XCTAssertTrue(short.contains(.riverfront))
        XCTAssertTrue(long.contains(.riverfront), "A compact fallback must survive the shortlist.")
    }

    func testEveryLoopReturnsToTheSelectedStartAndSumsEveryLeg() async throws {
        for loop in AustinLoop.allCases {
            let maps = TestMaps()
            let start = StartingPlace(name: "Public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.28, longitude: -97.76))
            let request = RideRequest(startingPlace: start, duration: .sixty)
            let route = try await MapKitRoutePlanner(maps: maps).plan(request, loop: loop)
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
                let route = try await MapKitRoutePlanner(maps: maps).plan(request, loop: loop)
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
        let model = RoutePreviewModel(planner: MapKitRoutePlanner(maps: maps))
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
        let start = StartingPlace(name: "Public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.295, longitude: -97.77))
        let route = try await MapKitRoutePlanner(maps: maps).plan(RideRequest(startingPlace: start, duration: .thirty), loop: .parks)
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
                             coordinate: CLLocationCoordinate2D(latitude: 30.29 + Double(resolutions) * 0.005, longitude: -97.77), isStop: anchor.isStop)
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
    let points = [RouteWaypoint(id: "start", name: start.name, detail: "", coordinate: start.coordinate),
                  RouteWaypoint(id: "return", name: start.name, detail: "", coordinate: start.coordinate)]
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
