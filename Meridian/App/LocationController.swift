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

        let reverseGeoCoder = CLGeocoder()

        reverseGeoCoder.reverseGeocodeLocation(locations[0]) { [weak self] placemarks, _ in
            guard let self, let customLabel = placemarks?.first?.locality else { return }
            self.updateHomeObject(with: customLabel, coordinates: coordinates)
            self.locationManager.stopUpdatingLocation()
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
