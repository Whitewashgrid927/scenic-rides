import MapKit
import Observation

@MainActor
protocol RouteMapServing {
    func resolve(_ anchor: RouteAnchor) async throws -> RouteWaypoint
    func directions(from: RouteWaypoint, to: RouteWaypoint, departure: Date, preferences: RoadPreferences) async throws -> RouteLeg
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
        for anchor in loop.anchors(options: request.options) {
            try Task.checkCancellation()
            waypoints.append(try await maps.resolve(anchor))
        }
        waypoints.append(RouteWaypoint(id: "return", name: start.name, detail: start.detail, coordinate: start.coordinate))

        var legs: [RouteLeg] = []
        var departure = request.departure
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
                leg = try await maps.directions(from: source, to: destination, departure: departure, preferences: request.options.roads)
            }
            try Task.checkCancellation()
            guard leg.distance.isFinite, leg.distance >= 0,
                  leg.expectedTravelTime.isFinite, leg.expectedTravelTime >= 0,
                  leg.polyline.pointCount >= 2 else { throw RoutePlanningError.unavailable }
            legs.append(leg)
            departure = departure.addingTimeInterval(leg.expectedTravelTime)
            if destination.isStop {
                departure = departure.addingTimeInterval(request.options.stopTime)
            }
        }
        // Publish only a complete round trip; a failed return leg must not become a partial route.
        return ScenicRoute(loop: loop, waypoints: waypoints, legs: legs, options: request.options)
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
        request.resultTypes = anchor.isStop ? [.address, .pointOfInterest] : .address
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
            note: anchor.note,
            isStop: anchor.isStop
        )
        resolvedPlaces[anchor.id] = waypoint
        return waypoint
    }

    static func directionsRequest(from source: RouteWaypoint, to destination: RouteWaypoint, departure: Date, preferences: RoadPreferences) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = mapItem(source)
        request.destination = mapItem(destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        request.tollPreference = preferences.avoidTolls ? .avoid : .any
        request.highwayPreference = preferences.avoidHighways ? .avoid : .any
        request.departureDate = departure
        return request
    }

    func directions(from source: RouteWaypoint, to destination: RouteWaypoint, departure: Date, preferences: RoadPreferences) async throws -> RouteLeg {
        let request = Self.directionsRequest(from: source, to: destination, departure: departure, preferences: preferences)
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

    private static func mapItem(_ point: RouteWaypoint) -> MKMapItem {
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
        case ready(ScenicRoute)
        case failed
    }

    private(set) var states: [AustinLoop: State] = [:]
    private(set) var isLoading = true
    private(set) var checkedCount = 0
    private(set) var candidateCount = 0
    private(set) var failure: RoutePlanningError?
    private let planner: any RoutePlanning
    private var generation = UUID()
    private var request: RideRequest?

    init(planner: any RoutePlanning = MapKitRoutePlanner()) { self.planner = planner }

    func route(for loop: AustinLoop) -> ScenicRoute? {
        if case let .ready(route) = states[loop] { return route }
        return nil
    }

    private var completedRoutes: [ScenicRoute] {
        states.values.compactMap { if case let .ready(route) = $0 { route } else { nil } }
    }

    var routes: [ScenicRoute] {
        guard let request else { return [] }
        // Fill the available time as closely as possible, without exceeding it.
        return Array(completedRoutes.filter { $0.fits(request) }.sorted {
            if $0.totalTime != $1.totalTime { return $0.totalTime > $1.totalTime }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.loop.rawValue < $1.loop.rawValue
        }.prefix(3))
    }

    var shortestMinutes: Int? { completedRoutes.map(\.minutes).min() }
    var hasFailures: Bool { states.values.contains { if case .failed = $0 { true } else { false } } }

    func loadChoices(_ request: RideRequest, loops: [AustinLoop]? = nil) async {
        let token = UUID()
        generation = token
        if self.request?.id != request.id {
            states = [:]
        }
        self.request = request
        failure = nil
        isLoading = true
        defer { if generation == token { isLoading = false } }
        let choices = loops ?? AustinLoop.candidates(for: request)
        candidateCount = choices.count
        checkedCount = choices.filter { route(for: $0) != nil }.count
        guard !request.scenery.isEmpty else { failure = .invalidPreferences; return }
        guard request.options.stopTime < request.budget else { failure = .stopExceedsBudget; return }
        guard AustinLoop.supports(request.startingPlace.coordinate) else { failure = .outsideAustin; return }

        // Bound and sequence network work. Retry only failed choices, retaining
        // complete routes (including over-budget results) for this request.
        for loop in choices where route(for: loop) == nil {
            guard !Task.isCancelled, generation == token else { return }
            do {
                let route = try await planner.plan(request, loop: loop)
                try Task.checkCancellation()
                guard generation == token else { return }
                states[loop] = .ready(route)
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                states[loop] = .failed
            }
            checkedCount += 1
        }
        guard !Task.isCancelled, generation == token else { return }
        if completedRoutes.isEmpty { failure = .unavailable }
    }
}
