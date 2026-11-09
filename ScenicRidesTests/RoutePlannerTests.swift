import MapKit
import XCTest
@testable import ScenicRides

@MainActor
final class RoutePlannerTests: XCTestCase {
    func testStylesHaveDistinctChoicesAndSurpriseHasVariety() {
        for style in [RideStyle.water, .hills, .city] {
            let choices = AustinLoop.suggestions(style: style, duration: .thirty)
            XCTAssertEqual(choices.count, 2)
            XCTAssertEqual(Set(choices).count, 2)
            XCTAssertTrue(choices.allSatisfy { $0.style == style })
            XCTAssertEqual(AustinLoop.suggestions(style: style, duration: .ninety), choices.reversed())
        }
        let surprise = AustinLoop.suggestions(style: .surprise, duration: .sixty)
        XCTAssertEqual(Set(surprise.map(\.style)), [.water, .hills, .city])
    }

    func testOptionalStopAndRoadPreferencesApplyToEveryLeg() async throws {
        for loop in AustinLoop.allCases {
            for kind in RideStopKind.allCases {
                let maps = TestMaps()
                let options = RideOptions(pace: .stop, stopKind: kind, roads: RoadPreferences(avoidHighways: true, avoidTolls: false))
                let request = RideRequest(startingPlace: .austin, duration: .sixty, style: loop.style, options: options)
                let route = try await MapKitRoutePlanner(maps: maps).plan(request, loop: loop)
                XCTAssertEqual(route.highlights.filter(\.isStop).count, 1)
                XCTAssertEqual(route.waypoints.count, 6)
                XCTAssertEqual(route.legs.count, 5)
                XCTAssertEqual(route.options, options)
                XCTAssertEqual(maps.roadPreferences, Array(repeating: options.roads, count: 5))
                XCTAssertEqual(route.waypoints.last?.coordinate.longitude, request.startingPlace.longitude)
            }
        }
    }

    func testMapKitReceivesBothRoadPreferencesIncludingTheirOffStates() {
        let point = RouteWaypoint(id: "start", name: "Austin", detail: "", coordinate: StartingPlace.austin.coordinate)
        for avoid in [true, false] {
            let request = AppleRouteMapService.directionsRequest(from: point, to: point, departure: Date(), preferences: RoadPreferences(avoidHighways: avoid, avoidTolls: !avoid))
            XCTAssertEqual(request.highwayPreference, avoid ? .avoid : .any)
            XCTAssertEqual(request.tollPreference, avoid ? .any : .avoid)
            XCTAssertEqual(request.transportType, .automobile)
        }
    }

    func testRetryPreservesSuccessfulAlternativeAndNewRequestClearsCache() async {
        let maps = TestMaps()
        maps.failAtLeg = 4
        let model = RoutePreviewModel(planner: MapKitRoutePlanner(maps: maps))
        let request = RideRequest(startingPlace: .austin, duration: .sixty)
        await model.loadChoices(request, loops: [.parks, .riverside], prioritizing: .parks)
        XCTAssertNil(model.route(for: .parks))
        let cachedID = model.route(for: .riverside)?.id
        XCTAssertNotNil(cachedID)
        let before = maps.journeys.count
        maps.failAtLeg = nil
        await model.loadChoices(request, loops: [.parks, .riverside], prioritizing: .parks)
        XCTAssertEqual(maps.journeys.count - before, 4)
        XCTAssertEqual(model.route(for: .riverside)?.id, cachedID)
        let newStart = StartingPlace(name: "Another public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.28, longitude: -97.75))
        let changed = RideRequest(startingPlace: newStart, duration: .sixty)
        await model.loadChoices(changed, loops: [.parks], prioritizing: .parks)
        XCTAssertNil(model.route(for: .riverside))
        XCTAssertEqual(model.route(for: .parks)?.waypoints.first?.coordinate.latitude, newStart.latitude)
    }

    func testEveryLoopRoutesBackToTheSelectedStartAndSumsAllLegs() async throws {
        for loop in AustinLoop.allCases {
            let maps = TestMaps()
            let start = StartingPlace(name: "Public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.28, longitude: -97.76))
            let route = try await MapKitRoutePlanner(maps: maps).plan(
                RideRequest(startingPlace: start, duration: .sixty), loop: loop
            )
            XCTAssertEqual(maps.journeys.count, 4)
            XCTAssertEqual(route.highlights.count, 3)
            XCTAssertFalse(route.highlights.contains(where: \.isStop))
            XCTAssertEqual(maps.journeys.first?.0.coordinate.latitude, start.latitude)
            XCTAssertEqual(maps.journeys.last?.1.coordinate.latitude, start.latitude)
            XCTAssertEqual(maps.journeys.last?.1.coordinate.longitude, start.longitude)
            XCTAssertEqual(route.distance, 6_437.376, accuracy: 0.001)
            XCTAssertEqual(route.expectedTravelTime, 1_200)
            XCTAssertEqual(route.minutes, 20, "The actual ETA must not be replaced by the target duration.")
            for index in 1..<maps.departures.count {
                XCTAssertEqual(maps.departures[index].timeIntervalSince(maps.departures[index - 1]), 300)
            }
            for waypoint in route.waypoints {
                XCTAssertTrue(route.mapRect.contains(MKMapPoint(waypoint.coordinate)))
            }
        }
    }

    func testFailedReturnLegNeverPublishesAPartialRoundTripAndRetryRecovers() async {
        let maps = TestMaps()
        maps.failAtLeg = 4
        let model = RoutePreviewModel(planner: MapKitRoutePlanner(maps: maps))
        let request = RideRequest(startingPlace: .austin, duration: .sixty)
        await model.loadChoices(request, loops: [.hills], prioritizing: .hills)
        XCTAssertNil(model.route(for: .hills))
        guard case .failed = model.state(for: .hills) else { return XCTFail("Expected a route error") }
        maps.failAtLeg = nil
        await model.loadChoices(request, loops: [.hills], prioritizing: .hills)
        XCTAssertEqual(model.route(for: .hills)?.legs.count, 4)
    }

    func testStartingAtAHighlightSkipsTheZeroLengthDrivingRequest() async throws {
        let maps = TestMaps()
        let start = StartingPlace(name: "Public starting point", detail: "Austin", coordinate: CLLocationCoordinate2D(latitude: 30.295, longitude: -97.77))
        let route = try await MapKitRoutePlanner(maps: maps).plan(RideRequest(startingPlace: start, duration: .thirty), loop: .parks)
        XCTAssertEqual(maps.journeys.count, 3)
        XCTAssertEqual(route.legs.count, 4)
        XCTAssertEqual(route.legs.first?.expectedTravelTime, 0)
        XCTAssertEqual(route.expectedTravelTime, 900)
        XCTAssertEqual(route.waypoints.last?.coordinate.latitude, start.latitude)
    }

    func testOutsideAustinIsRejectedBeforeNetworkWork() async {
        let maps = TestMaps()
        let start = StartingPlace(name: "Outside Austin", detail: "", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060))
        do {
            _ = try await MapKitRoutePlanner(maps: maps).plan(RideRequest(startingPlace: start, duration: .thirty), loop: .parks)
            XCTFail("Expected an Austin-only error")
        } catch {
            XCTAssertEqual(error as? RoutePlanningError, .outsideAustin)
        }
        XCTAssertEqual(maps.resolutions, 0)
        XCTAssertTrue(maps.journeys.isEmpty)
    }

    func testOlderResponseCannotReplaceTheLatestLoop() async {
        let planner = DeferredPlanner()
        let model = RoutePreviewModel(planner: planner)
        let request = RideRequest(startingPlace: .austin, duration: .sixty)
        let first = Task { await model.loadChoices(request, loops: [.hills], prioritizing: .hills) }
        await planner.waitForRequest(.hills)
        let second = Task { await model.loadChoices(request, loops: [.lake], prioritizing: .lake) }
        await planner.waitForRequest(.lake)
        planner.finish(.lake)
        await second.value
        planner.finish(.hills)
        await first.value
        XCTAssertEqual(model.route(for: .lake)?.loop, .lake)
    }

    func testCancelledResponseIsDiscarded() async {
        let planner = DeferredPlanner()
        let model = RoutePreviewModel(planner: planner)
        let request = RideRequest(startingPlace: .austin, duration: .sixty)
        let task = Task { await model.loadChoices(request, loops: [.hills], prioritizing: .hills) }
        await planner.waitForRequest(.hills)
        task.cancel()
        planner.finish(.hills)
        await task.value
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
        journeys.append((from, to))
        departures.append(departure)
        if journeys.count == failAtLeg { throw RoutePlanningError.unavailable }
        let coordinates = [from.coordinate, to.coordinate]
        return RouteLeg(polyline: MKPolyline(coordinates: coordinates, count: 2), distance: 1_609.344, expectedTravelTime: 300)
    }
}

@MainActor
private final class DeferredPlanner: RoutePlanning {
    private var pending: [AustinLoop: CheckedContinuation<ScenicRoute, any Error>] = [:]
    private var observers: [AustinLoop: CheckedContinuation<Void, Never>] = [:]

    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        try await withCheckedThrowingContinuation { continuation in
            pending[loop] = continuation
            observers.removeValue(forKey: loop)?.resume()
        }
    }

    func waitForRequest(_ loop: AustinLoop) async {
        if pending[loop] != nil { return }
        await withCheckedContinuation { observers[loop] = $0 }
    }

    func finish(_ loop: AustinLoop) {
        pending.removeValue(forKey: loop)?.resume(returning: ScenicRoute(loop: loop, waypoints: [], legs: []))
    }
}
