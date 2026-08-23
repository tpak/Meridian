// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLocation
import CoreLoggerKit
import CoreModelKit

protocol LocationControllerDelegate: AnyObject {
    func didChangeAuthorizationStatus()
}

class LocationController: NSObject {
    private let store: DataStore
    private let geocoder: GeocodingServicing

    /// Notified whenever authorization changes. On denial the current-location row's coordinates
    /// are cleared (see `updateHomeObject`), and `formattedSunriseTime` renders nothing without
    /// them — so the delegate is what re-seeds them from the city-name backfill. Without it,
    /// declining the prompt would leave the sunrise/sunset line blank until the next launch.
    weak var delegate: LocationControllerDelegate?

    init(withStore dataStore: DataStore, geocoder: GeocodingServicing = MapKitGeocodingService()) {
        store = dataStore
        self.geocoder = geocoder
        super.init()
    }

    private var locationManager: CLLocationManager = {
        let locationManager = CLLocationManager()
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        return locationManager
    }()

    func authorizationStatus() -> CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }

    func locationAccessNotDetermined() -> Bool {
        return locationManager.authorizationStatus == .notDetermined
    }

    func locationAccessGranted() -> Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    func locationAccessDenied() -> Bool {
        let status = locationManager.authorizationStatus
        return status == .restricted || status == .denied
    }

    func setDelegate() {
        locationManager.delegate = self
    }

    func determineAndRequestLocationAuthorization() {
        setDelegate()

        // Ask explicitly rather than letting startUpdatingLocation() raise the prompt as a side
        // effect. macOS shows it once and remembers the answer; a second launch goes straight to
        // the already-resolved branch below.
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Never raise a system permission dialog out of a test process — it would block the
            // runner on any machine that hasn't answered the prompt yet.
            guard NSClassFromString("XCTestCase") == nil else { return }
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            handleAuthorizationChange(locationManager.authorizationStatus)
        default:
            locationManager.startUpdatingLocation()
        }
    }

    /// Shared body for both authorization callbacks (see the delegate extension for why there are
    /// two). Clearing coordinates on denial is deliberate — holding a position after the user
    /// revokes access would be keeping data they just took back — and the delegate hand-off is what
    /// stops that from leaving the sunrise/sunset line blank.
    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .denied, .restricted:
            updateHomeObject(with: TimeZone.autoupdatingCurrent.identifier, coordinates: nil)
            locationManager.stopUpdatingLocation()
            delegate?.didChangeAuthorizationStatus()
        case .notDetermined:
            break // Nothing to do until the user answers the prompt.
        default:
            locationManager.startUpdatingLocation()
        }
    }

    private func updateHomeObject(with _: String, coordinates: CLLocationCoordinate2D?) {
        // Refresh sunrise/sunset coordinates on the current home row only.
        // When `coordinates` is nil (authorization revoked) the row's lat/
        // long are cleared so sunrise/sunset stop computing against stale
        // values. The label parameter is preserved for call-site
        // compatibility but intentionally NOT applied — letting reverse
        // geocoding overwrite a user-chosen customLabel like "Home" or
        // "Melbourne" is hostile.
        let updated: [Data] = store.timezones().compactMap { data in
            guard let model = TimezoneData.customObject(from: data) else { return data }
            if model.isSystemTimezone {
                model.latitude = coordinates?.latitude
                model.longitude = coordinates?.longitude
            }
            return NSKeyedArchiver.secureArchive(with: model) ?? data
        }
        store.setTimezones(updated)
    }
}

extension LocationController: CLLocationManagerDelegate {
    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let firstLocation = locations.first else { return }
        let coordinates = firstLocation.coordinate

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.locationManager.stopUpdatingLocation() }

            do {
                let places = try await self.geocoder.reverse(location: firstLocation)
                guard let cityName = places.first?.cityName else { return }
                self.updateHomeObject(with: cityName, coordinates: coordinates)
            } catch {
                Logger.production("Reverse geocode failed: \((error as NSError).domain) \((error as NSError).code)")
            }
        }
    }

    /// The current callback. `locationManager(_:didChangeAuthorization:)` below was deprecated in
    /// macOS 11 and this project deploys to 26 — CoreLocation prefers this one when both exist, so
    /// without it the denial fallback would quietly never run.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager.authorizationStatus)
    }

    /// Retained for older systems (and exercised directly by the unit tests, which can't make the
    /// system deliver a real authorization change). Routes to the same place as the modern callback.
    func locationManager(_: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationChange(status)
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        Logger.production("Location error: \((error as NSError).domain) \((error as NSError).code)")
    }
}
