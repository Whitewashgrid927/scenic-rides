import CoreLocation
import MapKit

enum RideDuration: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }
    var label: String { "\(rawValue) min" }
}

struct StartingPlace: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double

    init(name: String, detail: String, coordinate: CLLocationCoordinate2D) {
        self.id = UUID()
        self.name = name
        self.detail = detail
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // A city-level starting selection, not a simulated device location.
    static let austin = StartingPlace(
        name: "Austin, TX",
        detail: "Austin, Texas",
        coordinate: CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7431)
    )

    static let austinMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.318, longitude: -97.765),
        span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.15)
    )
}

struct RideRequest: Identifiable {
    let id = UUID()
    let startingPlace: StartingPlace
    let duration: RideDuration
    var style: RideStyle = .water
    var options = RideOptions()
    // Every ride in this version returns to its starting point.
}

enum RideStyle: String, CaseIterable, Identifiable {
    case water, hills, city, surprise
    var id: String { rawValue }
    var name: String {
        switch self {
        case .water: "Water views"
        case .hills: "Hills & curves"
        case .city: "City lights"
        case .surprise: "Surprise me"
        }
    }
    var symbol: String {
        switch self {
        case .water: "water.waves"
        case .hills: "mountain.2"
        case .city: "building.2"
        case .surprise: "shuffle"
        }
    }
}

enum RidePace: String, CaseIterable, Identifiable {
    case drive, stop
    var id: String { rawValue }
    var name: String { self == .drive ? "Just drive" : "Include a stop" }
}

enum RideStopKind: String, CaseIterable, Identifiable {
    case coffee, view, walk
    var id: String { rawValue }
    var name: String {
        switch self {
        case .coffee: "Coffee"
        case .view: "A view"
        case .walk: "A short walk"
        }
    }
    var symbol: String {
        switch self {
        case .coffee: "cup.and.saucer"
        case .view: "mountain.2"
        case .walk: "figure.walk"
        }
    }
}

struct RoadPreferences: Equatable {
    var avoidHighways = false
    var avoidTolls = true
}

struct RideOptions: Equatable {
    var pace: RidePace = .drive
    var stopKind: RideStopKind = .view
    var roads = RoadPreferences()

    var summary: String { pace == .drive ? pace.name : "Stop for \(stopKind.name.lowercased())" }
}
