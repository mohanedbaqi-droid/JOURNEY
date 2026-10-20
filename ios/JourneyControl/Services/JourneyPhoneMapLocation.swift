import CoreLocation
import SwiftUI

/// iPhone-only foreground map location. The value is never published to the
/// JOURNEY server, shared with the ESP, or used by keyless proximity control.
@MainActor
final class JourneyPhoneMapLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var observing = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    var permissionDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func start() {
        observing = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            coordinate = nil
        @unknown default:
            break
        }
    }

    func stop() {
        observing = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if permissionDenied {
            coordinate = nil
            manager.stopUpdatingLocation()
        } else if observing &&
                  (authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse) {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard observing,
              let location = locations.last,
              location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.timestamp.timeIntervalSinceNow > -120 else { return }
        coordinate = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Preserve the last valid foreground position on transient GPS errors.
        // Never substitute the vehicle GPS or an arbitrary map center for phone GPS.
        NSLog("[JOURNEY MAP] iPhone location unavailable: %@", error.localizedDescription)
    }
}
