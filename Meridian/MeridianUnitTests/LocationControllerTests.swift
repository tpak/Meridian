// Copyright © 2015 Abhishek Banthia

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

    func testDidChangeAuthorizationDeniedSetsLabelToCurrentTimezone() throws {
        let timezone = makeSystemTimezone(latitude: 37.7749, longitude: -122.4194)
        timezone.setLabel("Old Label")
        store.addTimezone(timezone)

        controller.locationManager(CLLocationManager(), didChangeAuthorization: .denied)

        let updated = try XCTUnwrap(TimezoneData.customObject(from: store.timezones()[0]))
        XCTAssertEqual(updated.customLabel, TimeZone.autoupdatingCurrent.identifier)
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

    // MARK: - didFailWithError

    func testDidFailWithError() {
        let error = NSError(domain: "CLErrorDomain", code: 0, userInfo: nil)
        // Should not crash — only logs
        controller.locationManager(CLLocationManager(), didFailWithError: error)
    }

    // MARK: - Helpers

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
