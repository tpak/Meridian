// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import CoreLocation
import XCTest
@testable import Meridian

/// Stub GeocodingServicing for tests. Returns whatever the test prepared,
/// or throws the prepared error. Records call arguments so tests can
/// assert on what the call site asked for.
final class MockGeocodingService: GeocodingServicing, @unchecked Sendable {
    var forwardResult: Result<[GeocodedPlace], Error> = .success([])

    private(set) var forwardCalls: [(address: String, timeout: TimeInterval)] = []

    func forward(addressString: String, timeout: TimeInterval) async throws -> [GeocodedPlace] {
        forwardCalls.append((addressString, timeout))
        return try forwardResult.get()
    }
}

private func makePlace(
    lat: Double = 0,
    lon: Double = 0,
    cityName: String? = nil,
    formattedAddress: String? = nil,
    regionCode: String? = nil,
    timeZone: TimeZone? = nil
) -> GeocodedPlace {
    GeocodedPlace(
        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        timeZone: timeZone,
        cityName: cityName,
        formattedAddress: formattedAddress,
        regionCode: regionCode
    )
}

class GeocodingServiceTests: XCTestCase {

    // MARK: - GeocodingServicing default-timeout convenience

    func testForwardDefaultTimeoutUsesGeocodingConstantsTimeout() async throws {
        let mock = MockGeocodingService()
        mock.forwardResult = .success([makePlace(cityName: "Anywhere")])

        _ = try await mock.forward(addressString: "anything")

        XCTAssertEqual(mock.forwardCalls.count, 1)
        XCTAssertEqual(mock.forwardCalls[0].timeout, GeocodingConstants.timeout)
    }

    // MARK: - NetworkManager.geocodeAddress wraps GeocodingServicing

    func testNetworkManagerGeocodeAddressReturnsFirstPlace() async throws {
        let mock = MockGeocodingService()
        let first = makePlace(lat: 1, lon: 2, cityName: "First")
        let second = makePlace(lat: 3, lon: 4, cityName: "Second")
        mock.forwardResult = .success([first, second])

        let result = try await NetworkManager.geocodeAddress("Tokyo", geocoder: mock)

        XCTAssertEqual(result.cityName, "First")
        XCTAssertEqual(result.coordinate.latitude, 1)
        XCTAssertEqual(result.coordinate.longitude, 2)
        XCTAssertEqual(mock.forwardCalls.first?.address, "Tokyo")
    }

    func testNetworkManagerGeocodeAddressThrowsOnEmptyResults() async {
        let mock = MockGeocodingService()
        mock.forwardResult = .success([])

        do {
            _ = try await NetworkManager.geocodeAddress("Atlantis", geocoder: mock)
            XCTFail("Expected throw on empty results")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "NetworkManager")
            XCTAssertEqual(error.code, 1)
        }
    }

    func testNetworkManagerGeocodeAddressPropagatesGeocoderError() async {
        let mock = MockGeocodingService()
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        mock.forwardResult = .failure(underlying)

        do {
            _ = try await NetworkManager.geocodeAddress("Tokyo", geocoder: mock)
            XCTFail("Expected throw")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, NSURLErrorDomain)
            XCTAssertEqual(error.code, NSURLErrorNotConnectedToInternet)
        }
    }

    // MARK: - GeocodedPlace shape

    func testGeocodedPlaceCarriesAllFields() {
        let tz = TimeZone(identifier: "Asia/Tokyo")
        let place = makePlace(
            lat: 35.6,
            lon: 139.7,
            cityName: "Tokyo",
            formattedAddress: "Tokyo, Japan",
            regionCode: "JP",
            timeZone: tz
        )

        XCTAssertEqual(place.coordinate.latitude, 35.6, accuracy: 0.0001)
        XCTAssertEqual(place.coordinate.longitude, 139.7, accuracy: 0.0001)
        XCTAssertEqual(place.cityName, "Tokyo")
        XCTAssertEqual(place.formattedAddress, "Tokyo, Japan")
        XCTAssertEqual(place.regionCode, "JP")
        XCTAssertEqual(place.timeZone, tz)
    }

    // MARK: - GeocodingError

    func testGeocodingErrorInvalidInputHasDescription() {
        XCTAssertEqual(GeocodingError.invalidInput.errorDescription, "Invalid geocoding input")
    }
}
