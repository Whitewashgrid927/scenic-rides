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
        try await Task.sleep(for: scenario == "loading" ? .seconds(30) : .milliseconds(250))
        if scenario == "retry", attempts == 1 { throw RoutePlanningError.unavailable }
        let start = request.startingPlace
        var points = [RouteWaypoint(id: "start", name: start.name, detail: start.detail, coordinate: start.coordinate)]
        let coordinates = [
            CLLocationCoordinate2D(latitude: 30.29, longitude: -97.78),
            CLLocationCoordinate2D(latitude: 30.32, longitude: -97.78),
            CLLocationCoordinate2D(latitude: 30.31, longitude: -97.75),
            CLLocationCoordinate2D(latitude: 30.28, longitude: -97.77)
        ]
        points += zip(loop.anchors(options: request.options), coordinates).map { anchor, coordinate in
            RouteWaypoint(id: anchor.id, name: anchor.name, detail: anchor.address, coordinate: coordinate, note: anchor.note, isStop: anchor.isStop)
        }
        points.append(RouteWaypoint(id: "return", name: start.name, detail: start.detail, coordinate: start.coordinate))
        let legs = zip(points, points.dropFirst()).map { source, destination in
            let coordinates = [source.coordinate, destination.coordinate]
            return RouteLeg(polyline: MKPolyline(coordinates: coordinates, count: coordinates.count), distance: 3_218.688, expectedTravelTime: 600)
        }
        return ScenicRoute(loop: loop, waypoints: points, legs: legs, options: request.options)
    }
}
#endif
