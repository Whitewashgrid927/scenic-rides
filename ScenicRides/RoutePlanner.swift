import MapKit
import Observation

@MainActor
protocol RouteMapServing {
    func resolve(_ anchor: RouteAnchor) async throws -> RouteWaypoint
    func directions(from: RouteWaypoint, to: RouteWaypoint, departure: Date) async throws -> RouteLeg
}

@MainActor
protocol RoutePlanning {
    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute
}

@MainActor
final class MapKitRoutePlanner: RoutePlanning {
    private let maps: any RouteMapServing

    init(maps: any RouteMapServing = AppleRouteMapService()) {
        self.maps = maps
    }

    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        guard AustinLoop.supports(request.startingPlace.coordinate) else {
            throw RoutePlanningError.outsideAustin
        }
        let start = request.startingPlace
        var waypoints = [RouteWaypoint(id: "start", name: start.name, detail: start.detail, coordinate: start.coordinate)]
        for anchor in loop.anchors {
            try Task.checkCancellation()
            waypoints.append(try await maps.resolve(anchor))
        }
        waypoints.append(RouteWaypoint(id: "return", name: start.name, detail: start.detail, coordinate: start.coordinate))

        var legs: [RouteLeg] = []
        var departure = Date()
        // Sequential requests avoid bursts and let each leg's ETA inform the next departure.
        for (source, destination) in zip(waypoints, waypoints.dropFirst()) {
            try Task.checkCancellation()
            let sourceLocation = CLLocation(latitude: source.coordinate.latitude, longitude: source.coordinate.longitude)
            let destinationLocation = CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
            let leg: RouteLeg
            if sourceLocation.distance(from: destinationLocation) < 5 {
                // Starting at a highlight needs no driving request for the coincident leg.
                let coordinates = [source.coordinate, destination.coordinate]
                leg = RouteLeg(polyline: MKPolyline(coordinates: coordinates, count: 2), distance: 0, expectedTravelTime: 0)
            } else {
                leg = try await maps.directions(from: source, to: destination, departure: departure)
            }
            try Task.checkCancellation()
            guard leg.distance.isFinite, leg.distance >= 0,
                  leg.expectedTravelTime.isFinite, leg.expectedTravelTime >= 0,
                  leg.polyline.pointCount >= 2 else { throw RoutePlanningError.unavailable }
            legs.append(leg)
            departure = departure.addingTimeInterval(leg.expectedTravelTime)
        }
        // Publish only a complete round trip; a failed return leg must not become a partial route.
        return ScenicRoute(loop: loop, waypoints: waypoints, legs: legs)
    }
}

@MainActor
final class AppleRouteMapService: RouteMapServing {
    private var resolvedPlaces: [String: RouteWaypoint] = [:]

    func resolve(_ anchor: RouteAnchor) async throws -> RouteWaypoint {
        if let cached = resolvedPlaces[anchor.id] { return cached }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = anchor.searchQuery
        request.region = StartingPlace.austinMapRegion
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        let cancellation = MapRequestCancellation { search.cancel() }
        let response = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await search.start()
        } onCancel: {
            Task { await cancellation.cancel() }
        }
        try Task.checkCancellation()
        guard let item = response.mapItems.first(where: { AustinLoop.supports($0.location.coordinate) }) else {
            throw RoutePlanningError.unavailable
        }
        let waypoint = RouteWaypoint(
            id: anchor.id,
            name: anchor.name,
            detail: item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? anchor.address,
            coordinate: item.location.coordinate,
            note: anchor.note
        )
        resolvedPlaces[anchor.id] = waypoint
        return waypoint
    }

    func directions(from source: RouteWaypoint, to destination: RouteWaypoint, departure: Date) async throws -> RouteLeg {
        let request = MKDirections.Request()
        request.source = mapItem(source)
        request.destination = mapItem(destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        request.tollPreference = .avoid
        request.departureDate = departure
        let directions = MKDirections(request: request)
        let cancellation = MapRequestCancellation { directions.cancel() }
        let response = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await directions.calculate()
        } onCancel: {
            Task { await cancellation.cancel() }
        }
        try Task.checkCancellation()
        guard let route = response.routes.first else { throw RoutePlanningError.unavailable }
        return RouteLeg(polyline: route.polyline, distance: route.distance, expectedTravelTime: route.expectedTravelTime)
    }

    private func mapItem(_ point: RouteWaypoint) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude), address: nil)
        item.name = point.name
        return item
    }
}

/// The global actor makes the cancellation handle safe to capture from onCancel.
@MainActor
private final class MapRequestCancellation {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() { action() }
}

@MainActor
@Observable
final class RoutePreviewModel {
    enum State {
        case loading
        case ready(ScenicRoute)
        case failed(RoutePlanningError)
    }

    private(set) var state: State = .loading
    private let planner: any RoutePlanning
    private var generation = UUID()

    init(planner: any RoutePlanning = MapKitRoutePlanner()) { self.planner = planner }

    var route: ScenicRoute? {
        if case let .ready(route) = state { return route }
        return nil
    }

    func load(_ request: RideRequest, loop: AustinLoop) async {
        let token = UUID()
        generation = token
        state = .loading
        do {
            let route = try await planner.plan(request, loop: loop)
            try Task.checkCancellation()
            guard generation == token else { return }
            state = .ready(route)
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            state = .failed(error as? RoutePlanningError ?? .unavailable)
        }
    }
}
