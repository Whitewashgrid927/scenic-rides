import MapKit

/// Only public destinations and approximate coordinates live in the bundled catalog.
/// Coordinates rank candidates; MapKit resolves and calculates the actual outing.
struct AustinCatalog: Decodable {
    let version: Int
    let anchors: [RouteAnchor]
    let stops: [ScenicStop]
    let routes: [AustinLoop]

    static let shared: Self = {
        guard let url = Bundle.main.url(forResource: "AustinCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? decode(data) else {
            return Self(version: 1, anchors: [], stops: [], routes: [])
        }
        return catalog
    }()

    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        let anchorIDs = Set(catalog.anchors.map(\.id))
        guard catalog.version == 1, !catalog.routes.isEmpty,
              anchorIDs.count == catalog.anchors.count,
              Set(catalog.stops.map(\.id)).count == catalog.stops.count,
              anchorIDs.isDisjoint(with: Set(catalog.stops.map(\.id))),
              Set(catalog.routes.map(\.id)).count == catalog.routes.count,
              Set(catalog.routes.map { Set($0.anchorIDs) }).count == catalog.routes.count,
              catalog.anchors.allSatisfy({ AustinLoop.supports($0.coordinate) && !$0.name.isEmpty && !$0.address.isEmpty }),
              catalog.stops.allSatisfy({ AustinLoop.supports($0.anchor.coordinate) && !$0.kinds.isEmpty && !$0.scenery.isEmpty && URL(string: $0.sourceURL)?.scheme == "https" }),
              catalog.routes.allSatisfy({ !$0.anchorIDs.isEmpty && Set($0.anchorIDs).count == $0.anchorIDs.count && Set($0.anchorIDs).isSubset(of: anchorIDs) && !$0.scenery.isEmpty && $0.planningMinutes > 0 }) else {
            throw CatalogError.invalid
        }
        return catalog
    }

    enum CatalogError: Error { case invalid }
}

struct ScenicStop: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let kinds: Set<RideStopKind>
    let scenery: Set<Scenery>
    let note: String
    let sourceURL: String

    var anchor: RouteAnchor {
        RouteAnchor(id: id, name: name, address: address, latitude: latitude, longitude: longitude,
                    note: note, isStop: true, scenery: scenery)
    }
}

struct StopPlacement {
    let stop: ScenicStop
    /// Insertion index in [start, scenic waypoints..., return].
    let index: Int
    let addedDistance: CLLocationDistance
}

/// Geographic shortlist only: driving distance and budget fit always come from MapKit.
enum NearbyStops {
    static func placements(for request: RideRequest, loop: AustinLoop, points: [CLLocationCoordinate2D], stops: [ScenicStop] = AustinCatalog.shared.stops) -> [StopPlacement] {
        guard request.options.pace == .stop, points.count >= 3 else { return [] }
        let scenicPoints = Array(points.dropFirst().dropLast())
        return stops.compactMap { stop -> StopPlacement? in
            let coordinate = stop.anchor.coordinate
            guard stop.kinds.contains(request.options.stopKind),
                  request.scenery.isSubset(of: loop.scenery.union(stop.scenery)),
                  scenicPoints.contains(where: { distance($0, coordinate) <= 3_000 }) else { return nil }
            let placements = (1..<points.count).map { index in
                StopPlacement(stop: stop, index: index, addedDistance: max(0,
                    distance(points[index - 1], coordinate) + distance(coordinate, points[index]) - distance(points[index - 1], points[index])))
            }
            guard let best = placements.min(by: { $0.addedDistance < $1.addedDistance }), best.addedDistance <= 5_000 else { return nil }
            return best
        }.sorted {
            $0.addedDistance == $1.addedDistance ? $0.stop.id < $1.stop.id : $0.addedDistance < $1.addedDistance
        }
    }

    static func distance(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}
