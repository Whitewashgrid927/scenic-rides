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
    private let stopRanker: any StopRanking
    private var rankingRequestID: UUID?
    private var rankedStops: [AustinLoop: RankedStops] = [:]

    init(maps: any RouteMapServing = AppleRouteMapService(), stopRanker: any StopRanking = OnDeviceStopRanker()) {
        self.maps = maps; self.stopRanker = stopRanker
    }

    func plan(_ request: RideRequest, loop: AustinLoop) async throws -> ScenicRoute {
        guard AustinLoop.supports(request.startingPlace.coordinate) else {
            throw RoutePlanningError.outsideAustin
        }
        if rankingRequestID != request.id { rankedStops = [:]; rankingRequestID = request.id }
        let start = request.startingPlace
        var stopSelection: StopSelectionMethod?
        var waypoints = [RouteWaypoint(id: "start", name: start.name, detail: start.detail, coordinate: start.coordinate)]
        for anchor in loop.anchors {
            try Task.checkCancellation()
            waypoints.append(try await maps.resolve(anchor))
        }
        waypoints.append(RouteWaypoint(id: "return", name: start.name, detail: start.detail, coordinate: start.coordinate))
        if request.options.pace == .stop {
            let nearby = NearbyStops.placements(for: request, loop: loop, points: waypoints.map(\.coordinate))
            guard !nearby.isEmpty else { throw RoutePlanningError.noNearbyStop }
            let ranked: RankedStops
            if rankingRequestID == request.id, let cached = rankedStops[loop] { ranked = cached }
            else {
                ranked = try await stopRanker.rank(nearby, request: request, loop: loop)
                try Task.checkCancellation()
                if ranked.method == .onDeviceAI, rankingRequestID == request.id { rankedStops[loop] = ranked }
            }
            stopSelection = ranked.method
            var chosen: (Int, RouteWaypoint)?
            // Bound place-resolution work; never substitute a distant stop or another kind.
            for placement in ranked.placements.prefix(2) {
                do {
                    let point = try await maps.resolve(placement.stop.anchor)
                    try Task.checkCancellation()
                    chosen = (placement.index, point)
                    break
                } catch {
                    try Task.checkCancellation()
                }
            }
            guard let (index, stop) = chosen else { throw RoutePlanningError.noNearbyStop }
            waypoints.insert(stop, at: index)
        }

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
        return ScenicRoute(loop: loop, waypoints: waypoints, legs: legs, options: request.options, stopSelection: stopSelection)
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
        guard let item = response.mapItems.first(where: { AustinLoop.supports($0.location.coordinate) && NearbyStops.distance($0.location.coordinate, anchor.coordinate) <= (anchor.isStop ? 350 : 1_500) }) else {
            throw RoutePlanningError.unavailable
        }
        let waypoint = RouteWaypoint(
            id: anchor.id,
            name: anchor.name,
            detail: item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? anchor.address,
            coordinate: item.location.coordinate,
            note: anchor.note,
            isStop: anchor.isStop,
            scenery: anchor.scenery
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
    enum State { case ready(ScenicRoute), failed }
    static let batchSize = 5
    private(set) var states: [AustinLoop: State] = [:]
    private(set) var routes: [ScenicRoute] = []
    private(set) var isLoading = true
    private(set) var batchCheckedCount = 0
    private(set) var batchCount = 0
    private(set) var batchMessage: String?
    private(set) var failure: RoutePlanningError?
    private var candidates: [AustinLoop] = []
    private let planner: any RoutePlanning
    private var generation = UUID()
    private var request: RideRequest?

    init(planner: any RoutePlanning = MapKitRoutePlanner()) { self.planner = planner }
    var checkedCount: Int { states.count }
    var candidateCount: Int { candidates.count }
    var hasFailures: Bool { states.values.contains { if case .failed = $0 { true } else { false } } }
    var canLoadMore: Bool { !unseenMatches.isEmpty || !unattempted.isEmpty }
    var shortestMinutes: Int? { completedRoutes.map(\.minutes).min() }
    private var unattempted: [AustinLoop] { candidates.filter { states[$0] == nil } }
    private var completedRoutes: [ScenicRoute] { states.values.compactMap { if case let .ready(route) = $0 { route } else { nil } } }
    private var unseenMatches: [ScenicRoute] {
        guard let request else { return [] }
        return completedRoutes.filter { route in route.fits(request) && !routes.contains { $0.loop == route.loop } }
    }

    func route(for loop: AustinLoop) -> ScenicRoute? {
        if case let .ready(route) = states[loop] { return route }
        return nil
    }

    func loadChoices(_ request: RideRequest, loops: [AustinLoop]? = nil) async {
        if self.request?.id == request.id {
            guard !isLoading else { return }
            let failed = candidates.filter { if case .failed = states[$0] { true } else { false } }
            await runBatch(Array(failed.prefix(Self.batchSize)))
            return
        }
        generation = UUID()
        self.request = request
        states = [:]; routes = []; candidates = []; batchMessage = nil; failure = nil
        batchCount = 0; batchCheckedCount = 0; isLoading = false
        guard !request.scenery.isEmpty else { failure = .invalidPreferences; return }
        guard request.options.stopTime < request.budget else { failure = .stopExceedsBudget; return }
        guard AustinLoop.supports(request.startingPlace.coordinate) else { failure = .outsideAustin; return }
        // Stable order also makes retries and pagination reproducible.
        var seen = Set<AustinLoop>()
        candidates = (loops ?? AustinLoop.candidates(for: request)).filter { seen.insert($0).inserted }
        guard !candidates.isEmpty else { failure = .noMatchingRoutes; return }
        await runBatch(Array(candidates.prefix(Self.batchSize)))
    }

    func loadMore() async {
        guard !isLoading, request != nil, canLoadMore else { return }
        // Reveal cached matches before spending another batch of MapKit requests.
        let next = unseenMatches.count >= 3 ? [] : Array(unattempted.prefix(Self.batchSize))
        await runBatch(next)
    }

    private func runBatch(_ choices: [AustinLoop]) async {
        guard let request else { return }
        let token = UUID(); generation = token
        isLoading = true; batchMessage = nil; failure = nil
        batchCount = choices.count; batchCheckedCount = 0
        let hadRoutes = !routes.isEmpty
        defer { if generation == token { isLoading = false } }
        for loop in choices {
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
            batchCheckedCount += 1
        }
        guard !Task.isCancelled, generation == token else { return }
        let previousCount = routes.count
        publishMatches(request)
        let added = routes.count - previousCount
        if hadRoutes {
            batchMessage = added > 0 ? "\(added) more \(added == 1 ? "route" : "routes") added." : "No new routes fit this budget."
        }
        if completedRoutes.isEmpty { failure = .unavailable }
    }

    private func publishMatches(_ request: RideRequest) {
        var remaining = unseenMatches
        for _ in 0..<3 {
            // Prefer a close time fit, with a penalty for reusing the same scenic waypoints.
            func score(_ route: ScenicRoute) -> Double {
                let anchors = Set(route.loop.anchorIDs)
                let overlap = routes.map { existing in
                    Double(anchors.intersection(existing.loop.anchorIDs).count) / Double(max(anchors.count, existing.loop.anchorIDs.count))
                }.max() ?? 0
                return (request.budget - route.totalTime) / 60 + overlap * 20
            }
            remaining.sort { score($0) == score($1) ? $0.loop.id < $1.loop.id : score($0) < score($1) }
            guard !remaining.isEmpty else { break }
            routes.append(remaining.removeFirst())
        }
    }
}
