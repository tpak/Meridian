// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLocation
import CoreLoggerKit
import CoreModelKit

/// Shared timezone search logic used by both PreferencesViewController and OnboardingSearchController.
enum TimezoneSearchService {
    /// Search local timezones matching the given query.
    static func searchLocalTimezones(_ query: String, in dataSource: SearchDataSource) {
        dataSource.searchTimezones(query.lowercased())
    }

    /// Perform a geocoding search using Apple's CLGeocoder.
    /// Returns an array of TimezoneData objects for matching places.
    @MainActor
    static func performGeocodingSearch(
        for searchString: String,
        dataSource: SearchDataSource
    ) async throws -> [TimezoneData] {
        let words = searchString.components(separatedBy: .whitespacesAndNewlines)
        let compactSearch = words.joined(separator: "")

        guard compactSearch.count >= 3 else {
            throw SearchError.queryTooShort
        }

        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.geocodeAddressString(compactSearch)

            guard !placemarks.isEmpty else {
                throw SearchError.zeroResults
            }

            let timezones: [TimezoneData] = placemarks.compactMap { placemark in
                guard let location = placemark.location else { return nil }
                let name = placemark.formattedAddress
                let timezoneID = placemark.timeZone?.identifier ?? ""
                let totalPackage: [String: Any] = [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    UserDefaultKeys.timezoneName: name,
                    UserDefaultKeys.customLabel: name,
                    UserDefaultKeys.timezoneID: timezoneID,
                    UserDefaultKeys.placeIdentifier: placemark.isoCountryCode ?? ""
                ]
                return TimezoneData(with: totalPackage)
            }

            guard !timezones.isEmpty else {
                throw SearchError.zeroResults
            }

            dataSource.setFilteredArrayValue(timezones)
            return timezones
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.network(error.localizedDescription)
        }
    }

    /// Errors that can occur during timezone search operations.
    enum SearchError: LocalizedError {
        case queryTooShort
        case offline
        case network(String)
        case zeroResults

        var errorDescription: String? {
            switch self {
            case .queryTooShort: return "Search query too short"
            case .offline: return PreferencesConstants.noInternetConnectivityError
            case .network(let message): return message
            case .zeroResults: return "No results! Try entering the exact name."
            }
        }
    }
}

// MARK: - CLPlacemark Helpers

extension CLPlacemark {
    /// A formatted address string built from available placemark components.
    var formattedAddress: String {
        let components = [locality, administrativeArea, country].compactMap { $0 }
        return components.isEmpty ? (name ?? "Unknown") : components.joined(separator: ", ")
    }
}
