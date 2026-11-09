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

/// Curated public corridors. Planning hints only choose a bounded shortlist;
/// live driving estimates decide whether a round trip fits the budget.
enum AustinLoop: Int, CaseIterable, Identifiable {
    case parks, riverside, hills, lake, skyline, eastside
    case riverAndHills, austinHighlights, hillCountry, grandAustin, riverfront, cityCenter
    var id: Int { rawValue }

    static func candidates(for request: RideRequest) -> [Self] {
        guard !request.scenery.isEmpty else { return [] }
        let matching = allCases.filter { request.scenery.isSubset(of: $0.scenery(options: request.options)) }
        let ordered = matching.sorted {
            let lhs = abs($0.planningMinutes + request.options.stopMinutes - request.duration.rawValue)
            let rhs = abs($1.planningMinutes + request.options.stopMinutes - request.duration.rawValue)
            return lhs == rhs ? $0.rawValue < $1.rawValue : lhs < rhs
        }
        var choices = Array(ordered.prefix(4))
        // Always check a compact matching alternative before declaring no fit.
        if let shortest = matching.min(by: { $0.planningMinutes < $1.planningMinutes }), !choices.contains(shortest) {
            choices.append(shortest)
        }
        return choices
    }

    var scenery: Set<Scenery> {
        switch self {
        case .parks, .riverside, .riverfront: [.water, .greenery, .city]
        case .hills, .lake, .hillCountry: [.water, .hills, .greenery]
        case .skyline, .eastside, .cityCenter: [.city]
        case .riverAndHills, .austinHighlights, .grandAustin: Set(Scenery.allCases)
        }
    }

    func scenery(options: RideOptions) -> Set<Scenery> {
        guard options.pace == .stop else { return scenery }
        switch options.stopKind {
        case .coffee: return scenery.union([.water])
        case .view: return scenery.union([.water, .hills, .greenery])
        case .walk: return scenery.union([.greenery, .city])
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
        case .riverAndHills: "River, hills & skyline"
        case .austinHighlights: "Austin highlights"
        case .hillCountry: "A little farther west"
        case .grandAustin: "The long scenic way"
        case .riverfront: "A moment by the river"
        case .cityCenter: "Around downtown"
        }
    }

    var symbol: String {
        switch self {
        case .hills, .lake, .hillCountry: "mountain.2"
        case .skyline, .eastside, .cityCenter: "building.2"
        case .grandAustin, .austinHighlights: "leaf"
        default: "water.waves"
        }
    }

    /// Approximate city-center values for shortlisting, never displayed as ETAs.
    private var planningMinutes: Int {
        switch self {
        case .parks: 25
        case .riverside: 25
        case .hills: 35
        case .lake: 30
        case .skyline: 25
        case .eastside: 20
        case .riverAndHills: 45
        case .austinHighlights: 55
        case .hillCountry: 65
        case .grandAustin: 80
        case .riverfront: 12
        case .cityCenter: 15
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
        case .riverAndHills: [.riversideRoad, .lakeAustin, .scenicDrive, .bonnellRoad]
        case .austinHighlights: [.southCongress, .bartonSprings, .redbudRoad, .westlakeDrive, .beeCaves, .capitol]
        case .hillCountry: [.lakeAustin, .scenicDrive, .bonnellRoad, .bullCreekRoad, .cityParkRoad]
        case .grandAustin: [.southCongress, .riversideRoad, .redbudRoad, .cityParkRoad, .bullCreekRoad, .bonnellRoad, .capitol]
        case .riverfront: [.riversideRoad]
        case .cityCenter: [.capitol, .lamar]
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
    static let bullCreekRoad = Self(id: "bull-creek-road", name: "Bull Creek area", address: "Lakewood Drive")
    static let cityParkRoad = Self(id: "city-park-road", name: "City Park Road", address: "City Park Rd & Pearce Rd")
    static let coffee = Self(id: "coffee-stop", name: "Mozart’s Coffee Roasters", address: "3825 Lake Austin Blvd", note: "Check opening hours before stopping.", isStop: true)
    static let mountBonnell = Self(id: "view-stop", name: "Mount Bonnell", address: "3800 Mount Bonnell Rd", note: "The overlook is reached on foot. Check access before stopping.", isStop: true)
    static let butlerPark = Self(id: "walk-stop", name: "Butler Park", address: "1000 Barton Springs Rd", note: "Check park access before stopping.", isStop: true)
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
    var drivingMinutes: Int { max(0, Int(ceil(expectedTravelTime / 60))) }
    var stopMinutes: Int { options.stopMinutes }
    var totalTime: TimeInterval { expectedTravelTime + options.stopTime }
    var minutes: Int { max(1, Int(ceil(totalTime / 60))) }
    var breakdown: String {
        stopMinutes > 0 ? "\(drivingMinutes) min drive + \(stopMinutes) min stop" : "\(drivingMinutes) min driving"
    }

    func fits(_ request: RideRequest) -> Bool {
        totalTime <= request.budget && request.scenery.isSubset(of: loop.scenery(options: options))
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
}
