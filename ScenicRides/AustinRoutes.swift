import MapKit

struct RouteAnchor: Identifiable {
    let id: String
    let name: String
    let address: String
    var note: String? = nil
    var isStop = false

    var searchQuery: String {
        isStop ? "\(name), \(address), Austin, Texas" : "\(address), Austin, Texas"
    }
}

/// Public roads and intersections shape drive-only loops; a selected stop is added separately.
enum AustinLoop: Int, CaseIterable, Identifiable {
    case parks, riverside, hills, lake, skyline, eastside
    var id: Int { rawValue }

    static func suggestions(style: RideStyle, duration: RideDuration) -> [Self] {
        let choices: [Self]
        switch style {
        case .water: choices = [.parks, .riverside]
        case .hills: choices = [.hills, .lake]
        case .city: choices = [.skyline, .eastside]
        case .surprise:
            // One choice from each style, chosen once when the preview is created.
            return [duration == .ninety ? .riverside : .parks,
                    duration == .ninety ? .lake : .hills,
                    duration == .ninety ? .eastside : .skyline].shuffled()
        }
        return duration == .ninety ? choices.reversed() : choices
    }

    var style: RideStyle {
        switch self {
        case .parks, .riverside: .water
        case .hills, .lake: .hills
        case .skyline, .eastside: .city
        }
    }

    var name: String {
        switch self {
        case .parks: "Lake & skyline"
        case .riverside: "Riverside loop"
        case .hills: "Hills & river"
        case .lake: "Westlake wander"
        case .skyline: "City & skyline"
        case .eastside: "East Austin loop"
        }
    }

    var anchors: [RouteAnchor] {
        switch self {
        case .parks: [.bartonSprings, .lakeAustin, .riversideRoad]
        case .riverside: [.lakeshore, .pleasantValley, .riversideRoad]
        case .hills: [.lakeAustin, .scenicDrive, .bonnellRoad]
        case .lake: [.redbudRoad, .westlakeDrive, .beeCaves]
        case .skyline: [.southCongress, .capitol, .lamar]
        case .eastside: [.eastSixth, .chicon, .holly]
        }
    }

    func anchors(options: RideOptions) -> [RouteAnchor] {
        guard options.pace == .stop else { return anchors }
        let stop: RouteAnchor
        switch options.stopKind {
        case .coffee: stop = .coffee
        case .view: stop = .mountBonnell
        case .walk: stop = .butlerPark
        }
        return anchors + [stop]
    }

    static func supports(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        let center = CLLocation(latitude: StartingPlace.austin.latitude, longitude: StartingPlace.austin.longitude)
        return center.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= 40_000
    }
}

private extension RouteAnchor {
    static let bartonSprings = Self(id: "barton-road", name: "Barton Springs Road", address: "Barton Springs Road & Azie Morton Road")
    static let lakeAustin = Self(id: "lake-road", name: "Lake Austin Boulevard", address: "Lake Austin Boulevard & Exposition Boulevard")
    static let riversideRoad = Self(id: "riverside-road", name: "Riverside Drive", address: "West Riverside Drive & South First Street")
    static let lakeshore = Self(id: "lakeshore-road", name: "Lakeshore Boulevard", address: "Lakeshore Boulevard & South Pleasant Valley Road")
    static let pleasantValley = Self(id: "pleasant-road", name: "Pleasant Valley Road", address: "South Pleasant Valley Road & East Cesar Chavez Street")
    static let scenicDrive = Self(id: "scenic-road", name: "Scenic Drive", address: "Scenic Drive")
    static let bonnellRoad = Self(id: "bonnell-road", name: "Mount Bonnell Road", address: "Mount Bonnell Road & Mount Bonnell Drive")
    static let redbudRoad = Self(id: "redbud-road", name: "Redbud Trail", address: "Redbud Trail & Lake Austin Boulevard")
    static let westlakeDrive = Self(id: "westlake-road", name: "Westlake Drive", address: "Westlake Drive & Redbud Trail")
    static let beeCaves = Self(id: "bee-caves-road", name: "Bee Caves Road", address: "Bee Caves Road & Westlake Drive")
    static let southCongress = Self(id: "congress-road", name: "South Congress", address: "South Congress Avenue & West Monroe Street")
    static let capitol = Self(id: "capitol-road", name: "Capitol district", address: "Congress Ave & E 11th St")
    static let lamar = Self(id: "lamar-road", name: "Lamar Boulevard", address: "W 6th St & N Lamar Blvd")
    static let eastSixth = Self(id: "sixth-road", name: "East Sixth Street", address: "East 6th Street & Comal Street")
    static let chicon = Self(id: "chicon-road", name: "East Austin", address: "Chicon Street & East Cesar Chavez Street")
    static let holly = Self(id: "holly-road", name: "Holly neighborhood", address: "Holly Street & Chicon Street")
    static let coffee = Self(id: "coffee-stop", name: "Mozart’s Coffee Roasters", address: "3825 Lake Austin Blvd", note: "Check opening hours before stopping.", isStop: true)
    static let mountBonnell = Self(id: "view-stop", name: "Mount Bonnell", address: "3800 Mount Bonnell Rd", note: "The overlook is reached on foot. Check access before stopping.", isStop: true)
    static let butlerPark = Self(id: "walk-stop", name: "Butler Park", address: "1000 Barton Springs Rd", note: "Time for a walk is extra. Check park access before stopping.", isStop: true)
}

struct RouteWaypoint: Identifiable {
    let id: String
    let name: String
    let detail: String
    let coordinate: CLLocationCoordinate2D
    var note: String? = nil
    var isStop = false
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
