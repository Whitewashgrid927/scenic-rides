#if DEBUG
import MapKit

/// Deterministic UI-test data. Release builds always use live MapKit directions.
@MainActor
final class PreviewTestRoutePlanner: RoutePlanning {
    private let scenario: String
    private var attempts = 0

    init(scenario: String) { self.scenario = scenario }

    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        attempts += 1
        try await Task.sleep(for: scenario == "loading" ? .seconds(30) : .milliseconds(100))
        if scenario == "retry", attempts <= AustinLoop.candidates(for: request).count { throw RoutePlanningError.unavailable }
        if scenario == "partial", attempts == 1 { throw RoutePlanningError.unavailable }
        let start = request.startingPlace
        var points = [RouteWaypoint(id: "start", name: start.name, detail: start.detail, coordinate: start.coordinate)]
        for (index, anchor) in loop.anchors(options: request.options).enumerated() {
            let coordinate = CLLocationCoordinate2D(latitude: 30.28 + Double(index) * 0.006, longitude: -97.77 - Double(index % 3) * 0.008)
            points.append(RouteWaypoint(id: anchor.id, name: anchor.name, detail: anchor.address, coordinate: coordinate, note: anchor.note, isStop: anchor.isStop))
        }
        points.append(RouteWaypoint(id: "return", name: start.name, detail: start.detail, coordinate: start.coordinate))
        let fixtureMinutes = [21, 24, 34, 27, 22, 18, 44, 53, 64, 78, 12, 14]
        let driving = TimeInterval(scenario == "overBudget" ? request.duration.rawValue + 5 : fixtureMinutes[loop.rawValue]) * 60
        let legCount = points.count - 1
        let legs = zip(points, points.dropFirst()).map { source, destination in
            let coordinates = [source.coordinate, destination.coordinate]
            return RouteLeg(polyline: MKPolyline(coordinates: coordinates, count: coordinates.count), distance: 1_609.344, expectedTravelTime: driving / Double(legCount))
        }
        return ScenicRoute(loop: loop, waypoints: points, legs: legs, options: request.options)
    }
}
#endif
