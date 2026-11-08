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
    // Every ride in this version returns to its starting point.
}
