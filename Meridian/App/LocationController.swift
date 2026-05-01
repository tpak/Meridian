// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLocation
import CoreLoggerKit
import CoreModelKit

protocol LocationControllerDelegate: AnyObject {
    func didChangeAuthorizationStatus()
}

class LocationController: NSObject {
    private let store: DataStore

    init(withStore dataStore: DataStore) {
        store = dataStore
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

        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
        }
    }

    private func updateHomeObject(with customLabel: String, coordinates: CLLocationCoordinate2D?) {
        let updated: [Data] = store.timezones().compactMap { data in
            guard let model = TimezoneData.customObject(from: data) else { return data }
            if model.isSystemTimezone {
                model.setLabel(customLabel)
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
        guard !locations.isEmpty, let coordinates = locations.first?.coordinate else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let geocoder = CLGeocoder()
            defer { self.locationManager.stopUpdatingLocation() }

            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(locations[0],
                                                                            timeout: GeocodingConstants.timeout)
                guard let customLabel = placemarks.first?.locality else { return }
                self.updateHomeObject(with: customLabel, coordinates: coordinates)
            } catch {
                Logger.production("Reverse geocode failed: \(error.localizedDescription)")
            }
        }
    }

    func locationManager(_: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .denied || status == .restricted {
            updateHomeObject(with: TimeZone.autoupdatingCurrent.identifier, coordinates: nil)
            locationManager.stopUpdatingLocation()
        } else if status == .notDetermined || status == .authorized || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        Logger.production("Location error: \(error.localizedDescription)")
    }
}

enum GeocodingConstants {
    /// Cap geocoding waits at 10 seconds. Apple's CLGeocoder has no built-in
    /// timeout — without one, a stalled network during location-permission
    /// grant or first-launch reverse geocode can hang the calling Task forever.
    static let timeout: TimeInterval = 10
}

extension CLGeocoder {
    /// Reverse-geocodes a location, racing against a timeout. On timeout the
    /// in-flight geocode is cancelled (CLGeocoder.cancelGeocode), which causes
    /// the awaited call to throw — the caller receives that error.
    func reverseGeocodeLocation(_ location: CLLocation, timeout: TimeInterval) async throws -> [CLPlacemark] {
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled {
                self.cancelGeocode()
            }
        }
        defer { timeoutTask.cancel() }
        return try await reverseGeocodeLocation(location)
    }

    /// Forward-geocodes an address string, racing against a timeout. Same
    /// cancellation behavior as the reverse variant.
    func geocodeAddressString(_ address: String, timeout: TimeInterval) async throws -> [CLPlacemark] {
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled {
                self.cancelGeocode()
            }
        }
        defer { timeoutTask.cancel() }
        return try await geocodeAddressString(address)
    }
}
