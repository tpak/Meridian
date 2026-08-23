// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import CoreLocation
import CoreModelKit
import XCTest

@testable import Meridian

class LocationControllerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var store: DataStore!
    private var controller: LocationController!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "LocationControllerTests")!
        testDefaults.removePersistentDomain(forName: "LocationControllerTests")
        store = DataStore(with: testDefaults)
        controller = LocationController(withStore: store)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "LocationControllerTests")
        testDefaults = nil
        store = nil
        controller = nil
        super.tearDown()
    }

    // MARK: - Init & Authorization

    func testInit() {
        XCTAssertNotNil(controller)
    }

    // MARK: - Delegate Setup

    func testSetDelegate() {
        // Should not crash
        controller.setDelegate()
    }

    func testDetermineAndRequestLocationAuthorization() {
        // Exercises all reachable switch branches; verifies fatalError is never hit
        controller.determineAndRequestLocationAuthorization()
    }

    // MARK: - didChangeAuthorization

    func testDidChangeAuthorizationDeniedClearsSystemTimezoneCoordinates() throws {
        let timezone = makeSystemTimezone(latitude: 37.7749, longitude: -122.4194)
        store.addTimezone(timezone)

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        let updated = try XCTUnwrap(TimezoneData.customObject(from: store.timezones()[0]))
        XCTAssertNil(updated.latitude)
        XCTAssertNil(updated.longitude)
    }

    func testDidChangeAuthorizationRestrictedClearsSystemTimezoneCoordinates() throws {
        let timezone = makeSystemTimezone(latitude: 37.7749, longitude: -122.4194)
        store.addTimezone(timezone)

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .restricted)

        let updated = try XCTUnwrap(TimezoneData.customObject(from: store.timezones()[0]))
        XCTAssertNil(updated.latitude)
        XCTAssertNil(updated.longitude)
    }

    func testDidChangeAuthorizationDeniedPreservesUserLabel() throws {
        // Revoking location permission must not overwrite the row's
        // user-chosen label. Only the geocoded coordinates are cleared.
        let timezone = makeSystemTimezone(latitude: 37.7749, longitude: -122.4194)
        timezone.setLabel("Home")
        store.addTimezone(timezone)

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        let updated = try XCTUnwrap(TimezoneData.customObject(from: store.timezones()[0]))
        XCTAssertEqual(updated.customLabel, "Home")
    }

    func testDidChangeAuthorizationPreservesNonSystemTimezones() throws {
        let timezone = TimezoneData()
        timezone.timezoneID = "America/New_York"
        timezone.formattedAddress = "New York"
        timezone.isSystemTimezone = false
        timezone.latitude = 40.7128
        timezone.longitude = -74.0060
        store.addTimezone(timezone)

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        let updated = try XCTUnwrap(TimezoneData.customObject(from: store.timezones()[0]))
        XCTAssertEqual(updated.latitude, 40.7128)
        XCTAssertEqual(updated.longitude, -74.0060)
        XCTAssertEqual(updated.formattedAddress, "New York")
    }

    func testDidChangeAuthorizationWithEmptyStore() {
        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)
        XCTAssertTrue(store.timezones().isEmpty)
    }

    func testDidChangeAuthorizationWithMixedTimezones() throws {
        let systemTz = makeSystemTimezone(latitude: 37.7749, longitude: -122.4194)
        let regularTz = TimezoneData()
        regularTz.timezoneID = "Europe/London"
        regularTz.formattedAddress = "London"
        regularTz.isSystemTimezone = false
        regularTz.latitude = 51.5074
        regularTz.longitude = -0.1278

        store.addTimezone(systemTz)
        store.addTimezone(regularTz)

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        let timezones = store.timezones()
        XCTAssertEqual(timezones.count, 2)

        let updatedSystem = try XCTUnwrap(TimezoneData.customObject(from: timezones[0]))
        XCTAssertNil(updatedSystem.latitude)
        XCTAssertNil(updatedSystem.longitude)
        XCTAssertTrue(updatedSystem.isSystemTimezone)

        let updatedRegular = try XCTUnwrap(TimezoneData.customObject(from: timezones[1]))
        XCTAssertEqual(updatedRegular.latitude, 51.5074)
        XCTAssertEqual(updatedRegular.longitude, -0.1278)
        XCTAssertFalse(updatedRegular.isSystemTimezone)
    }

    // MARK: - Denial hands back to the coordinate backfill (#199)

    /// Denial clears the row's coordinates, and `formattedSunriseTime` renders an empty string
    /// while they're nil — so the delegate callback is the only thing standing between "user
    /// declined" and "sunrise/sunset silently disappears until the next launch". Assert it fires.
    func testDenialNotifiesDelegate() {
        let spy = SpyLocationControllerDelegate()
        controller.delegate = spy
        store.addTimezone(makeSystemTimezone(latitude: 37.7749, longitude: -122.4194))

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        XCTAssertEqual(spy.statusChangeCount, 1, "denial must notify the delegate so it can refill coordinates")
    }

    func testRestrictionNotifiesDelegate() {
        let spy = SpyLocationControllerDelegate()
        controller.delegate = spy

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .restricted)

        XCTAssertEqual(spy.statusChangeCount, 1, "restricted is as unusable as denied and needs the same fallback")
    }

    /// The grant path must not invoke the fallback — refilling from the timezone-name geocode there
    /// would overwrite the precise coordinates we just asked the user for.
    func testAuthorizedDoesNotNotifyDelegate() {
        let spy = SpyLocationControllerDelegate()
        controller.delegate = spy

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedAlways)

        XCTAssertEqual(spy.statusChangeCount, 0, "granting access must not trigger the city-name fallback")
    }

    /// CoreLocation calls `locationManagerDidChangeAuthorization(_:)` in preference to the
    /// macOS 11-deprecated variant, so the fallback has to hang off the modern one too. This
    /// asserts both entry points reach the same place.
    ///
    /// Deliberately compares the two callbacks against each other rather than asserting a fixed
    /// count: the modern one reads `manager.authorizationStatus`, which is whatever the *machine*
    /// happens to be set to. An earlier version assumed a fresh CLLocationManager reports
    /// `.notDetermined` — true on a dev Mac that has already answered the prompt, false on a CI
    /// runner where location is denied, so it passed locally and broke main. The routing invariant
    /// is what this test is actually for, and it holds under any ambient status.
    func testModernAuthorizationCallbackRoutesToSameHandler() {
        let ambient = CLLocationManager().authorizationStatus

        let viaModern = SpyLocationControllerDelegate()
        controller.delegate = viaModern
        controller.locationManagerDidChangeAuthorization(CLLocationManager())

        let viaLegacy = SpyLocationControllerDelegate()
        controller.delegate = viaLegacy
        controller.locationManager(CLLocationManager(), didChangeAuthorization: ambient)

        XCTAssertEqual(viaModern.statusChangeCount, viaLegacy.statusChangeCount,
                       "both authorization callbacks must route to the same handler (ambient status: \(ambient.rawValue))")
    }

    /// Belt-and-braces on the same routing question, with statuses we control outright so the
    /// assertion is exact rather than relative.
    func testBothCallbackPathsAgreeForEveryExplicitStatus() {
        for status: CLAuthorizationStatus in [.denied, .restricted, .authorizedAlways, .notDetermined] {
            let spy = SpyLocationControllerDelegate()
            controller.delegate = spy
            controller.locationManager(CLLocationManager(), didChangeAuthorization: status)

            let expected = (status == .denied || status == .restricted) ? 1 : 0
            XCTAssertEqual(spy.statusChangeCount, expected,
                           "status \(status.rawValue) should\(expected == 1 ? "" : " not") trigger the fallback")
        }
    }

    func testDelegateIsHeldWeakly() {
        var spy: SpyLocationControllerDelegate? = SpyLocationControllerDelegate()
        controller.delegate = spy
        spy = nil
        XCTAssertNil(controller.delegate, "delegate must be weak — AppDelegate owns the controller")
    }

    // MARK: - didFailWithError

    func testDidFailWithError() {
        let error = NSError(domain: "CLErrorDomain", code: 0, userInfo: nil)
        // Should not crash — only logs
        controller.locationManager(CLLocationManager(), didFailWithError: error)
    }

    // MARK: - Helpers

    private final class SpyLocationControllerDelegate: LocationControllerDelegate {
        private(set) var statusChangeCount = 0
        func didChangeAuthorizationStatus() { statusChangeCount += 1 }
    }

    private func makeSystemTimezone(latitude: Double, longitude: Double) -> TimezoneData {
        let timezone = TimezoneData()
        timezone.timezoneID = TimeZone.autoupdatingCurrent.identifier
        timezone.formattedAddress = "System Location"
        timezone.isSystemTimezone = true
        timezone.latitude = latitude
        timezone.longitude = longitude
        return timezone
    }
}
