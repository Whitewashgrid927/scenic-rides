#if DEBUG
import MapKit

/// Deterministic states for UI checks; never included in Release builds.
@MainActor
final class PreviewTestRoutePlanner: RoutePlanning {
    private let scenario: String
    private var attempts = 0
    init(scenario: String) { self.scenario = scenario }

    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        attempts += 1
        try await Task.sleep(for: scenario == "loading" || (scenario == "loadingMore" && attempts > RoutePreviewModel.batchSize) ? .seconds(30) : .milliseconds(100))
        if scenario == "retry", attempts <= RoutePreviewModel.batchSize { throw RoutePlanningError.unavailable }
        if scenario == "partial", attempts == 1 { throw RoutePlanningError.unavailable }
        if scenario == "moreRetry", attempts == RoutePreviewModel.batchSize + 1 { throw RoutePlanningError.unavailable }
        let start = request.startingPlace
        var points = [RouteWaypoint(id: "start", name: start.name, detail: start.detail, coordinate: start.coordinate)]
        points += loop.anchors.map { RouteWaypoint(id: $0.id, name: $0.name, detail: $0.address, coordinate: $0.coordinate) }
        points.append(RouteWaypoint(id: "return", name: start.name, detail: start.detail, coordinate: start.coordinate))
        if request.options.pace == .stop {
            guard let chosen = loop.stopPlacements(for: request).first else { throw RoutePlanningError.noNearbyStop }
            let stop = chosen.stop.anchor
            points.insert(RouteWaypoint(id: stop.id, name: stop.name, detail: stop.address, coordinate: stop.coordinate, note: stop.note, isStop: true, scenery: stop.scenery), at: chosen.index)
        }
        let minutes = scenario == "overBudget" ? request.duration.rawValue + 5 : 20 + loop.id % 9
        let legCount = points.count - 1
        let legs = zip(points, points.dropFirst()).map { source, destination in
            let coordinates = [source.coordinate, destination.coordinate]
            return RouteLeg(polyline: MKPolyline(coordinates: coordinates, count: 2), distance: 1_609.344, expectedTravelTime: Double(minutes * 60) / Double(legCount))
        }
        return ScenicRoute(loop: loop, waypoints: points, legs: legs, options: request.options, stopSelection: request.options.pace == .stop ? (scenario == "aiReady" ? .onDeviceAI : .nearby(.unavailable)) : nil)
    }
}
#endif
