import MapKit

struct RouteAnchor: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    var note: String? = nil
    var isStop = false
    var scenery: Set<Scenery> = []

    private enum CodingKeys: String, CodingKey { case id, name, address, latitude, longitude }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var searchQuery: String { "\(address), Austin, Texas" }
}

struct AustinLoop: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let area: String
    let scenery: Set<Scenery>
    let planningMinutes: Double
    let symbol: String
    let anchorIDs: [String]
    var rawValue: Int { id }
    static var allCases: [Self] { AustinCatalog.shared.routes }
    var anchors: [RouteAnchor] {
        anchorIDs.compactMap { id in AustinCatalog.shared.anchors.first { $0.id == id } }
    }

    func stopPlacements(for request: RideRequest) -> [StopPlacement] {
        NearbyStops.placements(for: request, loop: self, points: [request.startingPlace.coordinate] + anchors.map(\.coordinate) + [request.startingPlace.coordinate])
    }

    /// Full ordered catalog, consumed in bounded batches by the preview model.
    static func candidates(for request: RideRequest) -> [Self] {
        guard !request.scenery.isEmpty else { return [] }
        let matching = allCases.filter { loop in
            request.options.pace == .stop ? !loop.stopPlacements(for: request).isEmpty : request.scenery.isSubset(of: loop.scenery)
        }
        func approach(_ loop: Self) -> Double {
            (loop.anchors.map { NearbyStops.distance(request.startingPlace.coordinate, $0.coordinate) }.min() ?? 0) / 1_000
        }
        func score(_ loop: Self) -> Double {
            abs(loop.planningMinutes + Double(request.options.stopMinutes - request.duration.rawValue)) + approach(loop) * 1.5
        }
        var ordered = matching.sorted { score($0) == score($1) ? $0.id < $1.id : score($0) < score($1) }
        // Include a compact, reachable alternative in the first five checks.
        if let compact = matching.min(by: {
            let lhs = $0.planningMinutes + approach($0) * 2
            let rhs = $1.planningMinutes + approach($1) * 2
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }), let index = ordered.firstIndex(of: compact), index >= 5 {
            ordered.remove(at: index); ordered.insert(compact, at: 4)
        }
        return ordered
    }

    static func supports(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate) && NearbyStops.distance(StartingPlace.austin.coordinate, coordinate) <= 40_000
    }
}

struct RouteWaypoint: Identifiable {
    let id: String
    let name: String
    let detail: String
    let coordinate: CLLocationCoordinate2D
    var note: String? = nil
    var isStop = false
    var scenery: Set<Scenery> = []
}

struct RouteLeg: Identifiable {
    let id = UUID()
    let polyline: MKPolyline
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

struct ScenicRoute: Identifiable {
    let id = UUID()
    let loop: AustinLoop
    /// Includes both the starting point and a final return to exactly that point.
    let waypoints: [RouteWaypoint]
    let legs: [RouteLeg]
    var options = RideOptions()
    var stopSelection: StopSelectionMethod? = nil

    var highlights: [RouteWaypoint] { Array(waypoints.dropFirst().dropLast()) }
    var distance: CLLocationDistance { legs.reduce(0) { $0 + $1.distance } }
    var expectedTravelTime: TimeInterval { legs.reduce(0) { $0 + $1.expectedTravelTime } }
    var drivingMinutes: Int { max(0, Int(ceil(expectedTravelTime / 60))) }
    var stopMinutes: Int { options.stopMinutes }
    var totalTime: TimeInterval { expectedTravelTime + options.stopTime }
    var minutes: Int { max(1, Int(ceil(totalTime / 60))) }
    var breakdown: String {
        stopMinutes > 0 ? "\(drivingMinutes) min drive + \(stopMinutes) min stop" : "\(drivingMinutes) min driving"
    }

    var stop: RouteWaypoint? { highlights.first(where: \.isStop) }
    var scenery: Set<Scenery> { highlights.filter(\.isStop).reduce(loop.scenery) { $0.union($1.scenery) } }
    func fits(_ request: RideRequest) -> Bool {
        options == request.options && totalTime.isFinite && totalTime <= request.budget
            && request.scenery.isSubset(of: scenery)
            && highlights.filter(\.isStop).count == (options.pace == .stop ? 1 : 0)
    }
    var distanceLabel: String {
        "\((distance / 1_609.344).formatted(.number.precision(.fractionLength(1)))) mi"
    }

    var mapRect: MKMapRect {
        var rect = legs.reduce(MKMapRect.null) { $0.union($1.polyline.boundingMapRect) }
        for waypoint in waypoints {
            let point = MKMapPoint(waypoint.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        return rect.insetBy(dx: -max(rect.width * 0.18, 1_000), dy: -max(rect.height * 0.18, 1_000))
    }
}

enum RoutePlanningError: Error, Equatable {
    case outsideAustin
    case unavailable
    case invalidPreferences
    case stopExceedsBudget
    case noMatchingRoutes
    case noNearbyStop
}
