import MapKit

struct RouteAnchor: Identifiable {
    let id: String
    let name: String
    let address: String
    var note: String? = nil

    var searchQuery: String { "\(name), \(address), Austin, Texas" }
}

/// Public places only. The duration chooses an initial loop, not a promised ETA.
enum AustinLoop: Int, CaseIterable, Identifiable {
    case parks, hills, lake

    var id: Int { rawValue }

    static func suggested(for duration: RideDuration) -> Self {
        switch duration {
        case .thirty: .parks
        case .sixty: .hills
        case .ninety: .lake
        }
    }

    var next: Self { Self(rawValue: (rawValue + 1) % Self.allCases.count)! }

    var name: String {
        switch self {
        case .parks: "Parks & skyline"
        case .hills: "Hills & river"
        case .lake: "Around Lake Austin"
        }
    }

    var anchors: [RouteAnchor] {
        switch self {
        case .parks: [.auditoriumShores, .zilker, .deepEddy]
        case .hills: [.redBud, .mountBonnell, .bullCreek]
        case .lake: [.mountBonnell, .emmaLong, .redBud]
        }
    }

    static func supports(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        let center = CLLocation(latitude: StartingPlace.austin.latitude, longitude: StartingPlace.austin.longitude)
        return center.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= 40_000
    }
}

private extension RouteAnchor {
    static let auditoriumShores = Self(id: "auditorium", name: "Auditorium Shores", address: "800 W Riverside Dr")
    static let zilker = Self(id: "zilker", name: "Zilker Metropolitan Park", address: "2100 Barton Springs Rd")
    static let deepEddy = Self(id: "deep-eddy", name: "Deep Eddy Pool", address: "401 Deep Eddy Ave")
    static let redBud = Self(id: "red-bud", name: "Red Bud Isle", address: "3401 Redbud Trl")
    static let mountBonnell = Self(id: "bonnell", name: "Mount Bonnell", address: "3800 Mount Bonnell Rd", note: "The overlook is reached on foot.")
    static let bullCreek = Self(id: "bull-creek", name: "Bull Creek District Park", address: "6701 Lakewood Dr")
    static let emmaLong = Self(id: "emma-long", name: "Emma Long Metropolitan Park", address: "1600 City Park Rd", note: "Park entry requires a day pass.")
}

struct RouteWaypoint: Identifiable {
    let id: String
    let name: String
    let detail: String
    let coordinate: CLLocationCoordinate2D
    var note: String? = nil
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

    var highlights: [RouteWaypoint] { Array(waypoints.dropFirst().dropLast()) }
    var distance: CLLocationDistance { legs.reduce(0) { $0 + $1.distance } }
    var expectedTravelTime: TimeInterval { legs.reduce(0) { $0 + $1.expectedTravelTime } }
    var minutes: Int { max(1, Int(ceil(expectedTravelTime / 60))) }
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
}
