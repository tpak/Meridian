// Copyright © 2015 Abhishek Banthia

import CoreModelKit
import Foundation

@testable import Meridian

// MARK: - Timezone Fixtures

/// Shared timezone dictionary fixtures used across test files
enum TestTimezones {
    // MARK: United States

    static var california: [String: Any] {
        return [
            "customLabel": "Test",
            "formattedAddress": "San Francisco",
            "place_id": "TestIdentifier",
            "timezoneID": "America/Los_Angeles",
            "nextUpdate": "",
            "latitude": "37.7749295",
            "longitude": "-122.4194155"
        ]
    }

    static var sanFrancisco: [String: Any] {
        return [
            "customLabel": "SF Office",
            "formattedAddress": "San Francisco",
            "place_id": "test-sf",
            "timezoneID": "America/Los_Angeles",
            "nextUpdate": "",
            "latitude": "37.7749295",
            "longitude": "-122.4194155"
        ]
    }

    static var newYork: [String: Any] {
        return [
            "customLabel": "NYC",
            "formattedAddress": "New York",
            "place_id": "TestNY",
            "timezoneID": "America/New_York",
            "nextUpdate": "",
            "latitude": 40.7128,
            "longitude": -74.0060
        ]
    }

    static var newYorkAlt: [String: Any] {
        return [
            "customLabel": "NYC",
            "formattedAddress": "New York",
            "place_id": "TestNY",
            "timezoneID": "America/New_York",
            "nextUpdate": "",
            "latitude": "40.7127753",
            "longitude": "-74.0059731"
        ]
    }

    static var florida: [String: Any] {
        return [
            "customLabel": "Gainesville",
            "formattedAddress": "Florida",
            "place_id": "ChIJvypWkWV2wYgR0E7HW9MTLvc",
            "timezoneID": "America/New_York",
            "nextUpdate": "",
            "latitude": "27.664827",
            "longitude": "-81.5157535"
        ]
    }

    static var omaha: [String: Any] {
        return [
            "timezoneID": "America/Chicago",
            "formattedAddress": "Omaha",
            "place_id": "ChIJ7fwMtciNk4cRBLY3rk9NQkY",
            "customLabel": "",
            "nextUpdate": "",
            "latitude": "41.2565369",
            "longitude": "-95.9345034"
        ]
    }

    // MARK: International

    static var mumbai: [String: Any] {
        return [
            "customLabel": "Ghar",
            "formattedAddress": "Mumbai",
            "place_id": "ChIJwe1EZjDG5zsRaYxkjY_tpF0",
            "timezoneID": "Asia/Calcutta",
            "nextUpdate": "",
            "latitude": "19.0759837",
            "longitude": "72.8776559"
        ]
    }

    static var mumbaiAlternate: [String: Any] {
        return [
            "customLabel": "Ghar",
            "formattedAddress": "Mumbai",
            "place_id": "ChIJwe1EZjDG5zsRaYxkjY_tpF0",
            "timezoneID": "Asia/Calcutta",
            "nextUpdate": "",
            "latitude": 19.0759837,
            "longitude": 72.8776559
        ]
    }

    static var tokyo: [String: Any] {
        return [
            "customLabel": "Tokyo",
            "formattedAddress": "Tokyo",
            "place_id": "TestTokyo",
            "timezoneID": "Asia/Tokyo",
            "nextUpdate": "",
            "latitude": 35.6762,
            "longitude": 139.6503
        ]
    }

    static var tokyoOffice: [String: Any] {
        return [
            "customLabel": "Tokyo Office",
            "formattedAddress": "Tokyo",
            "place_id": "test-tokyo",
            "timezoneID": "Asia/Tokyo",
            "nextUpdate": "",
            "latitude": "35.6761919",
            "longitude": "139.6503106"
        ]
    }

    static var london: [String: Any] {
        return [
            "customLabel": "London",
            "formattedAddress": "London",
            "place_id": "TestLondon",
            "timezoneID": "Europe/London",
            "nextUpdate": "",
            "latitude": 51.5074,
            "longitude": -0.1278
        ]
    }

    static var londonOffice: [String: Any] {
        return [
            "customLabel": "London Office",
            "formattedAddress": "London",
            "place_id": "test-london",
            "timezoneID": "Europe/London",
            "nextUpdate": "",
            "latitude": "51.5073509",
            "longitude": "-0.1277583"
        ]
    }

    static var auckland: [String: Any] {
        return [
            "customLabel": "Auckland",
            "formattedAddress": "New Zealand",
            "place_id": "ChIJh5Z3Fw4gLG0RM0dqdeIY1rE",
            "timezoneID": "Pacific/Auckland",
            "nextUpdate": "",
            "latitude": "-40.900557",
            "longitude": "174.885971"
        ]
    }

    static var onlyTimezone: [String: Any] {
        return [
            "timezoneID": "Africa/Algiers",
            "formattedAddress": "Africa/Algiers",
            "place_id": "",
            "customLabel": "",
            "nextUpdate": "",
            "latitude": "",
            "longitude": ""
        ]
    }

    static var noCoords: [String: Any] {
        return [
            "customLabel": "",
            "formattedAddress": "Africa/Algiers",
            "place_id": "",
            "timezoneID": "Africa/Algiers",
            "nextUpdate": "",
            "latitude": "",
            "longitude": ""
        ]
    }

    static var newYorkOffice: [String: Any] {
        return [
            "customLabel": "NY Office",
            "formattedAddress": "New York",
            "place_id": "test-ny",
            "timezoneID": "America/New_York",
            "nextUpdate": "",
            "latitude": "40.7127753",
            "longitude": "-74.0059728"
        ]
    }
}

// MARK: - DataStore Factory

/// Creates a test DataStore with isolated UserDefaults
/// - Parameter suiteName: Optional suite name for UserDefaults. If nil, generates a unique name.
/// - Returns: Tuple of (DataStore, UserDefaults) for cleanup
func makeTestDataStore(suiteName: String = "TestSuite-\(UUID().uuidString)") -> (DataStore, UserDefaults) {
    let defaults = UserDefaults(suiteName: suiteName)!
    let store = DataStore(with: defaults)
    return (store, defaults)
}

// MARK: - Timezone Persistence Helper

/// Saves a TimezoneData object to the provided DataStore
/// Used in tests that verify timezone storage and retrieval
/// - Parameters:
///   - timezone: The TimezoneData to save
///   - store: The DataStore to save to
///   - index: Optional index for insertion. If -1 (default), appends to the end.
func saveTimezoneToStore(_ timezone: TimezoneData, store: DataStore, at index: Int = -1) {
    var defaults = store.timezones()
    guard let encodedObject = NSKeyedArchiver.secureArchive(with: timezone as Any) else {
        return
    }
    index == -1 ? defaults.append(encodedObject) : defaults.insert(encodedObject, at: index)
    store.setTimezones(defaults)
}
