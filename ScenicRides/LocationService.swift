import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var currentPlace: StartingPlace?
    private(set) var isLocating = false
    var message: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func useCurrentLocation() {
        message = nil
        isLocating = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fail("Location access is off. You can search for a starting point instead.")
        @unknown default:
            fail("Your location is unavailable. Choose a starting point instead.")
        }
    }

    private func authorizationChanged() {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            fail("Location access is off. You can search for a starting point instead.")
        default:
            break
        }
    }

    private func fail(_ text: String) {
        isLocating = false
        message = text
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor [weak self] in
            self?.currentPlace = StartingPlace(
                name: "Current location",
                detail: "Your current location",
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
            self?.isLocating = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.fail("We couldn’t find your location. Try again or search for a starting point.")
        }
    }
}
