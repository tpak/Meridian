// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLocation

enum NetworkManager {
    static let internalServerError: NSError = {
        let localizedError = """
        There was a problem retrieving your information. Please try again later.
        If the problem continues please contact App Support.
        """
        let userInfoDictionary: [String: Any] = [NSLocalizedDescriptionKey: "Internal Error",
                                                 NSLocalizedFailureReasonErrorKey: localizedError]
        let error = NSError(domain: "APIError", code: 100, userInfo: userInfoDictionary)
        return error
    }()

    static let unableToGenerateURL: NSError = {
        let localizedError = """
        There was a problem searching the location. Please try again later.
        If the problem continues please contact App Support.
        """
        let userInfoDictionary: [String: Any] = [NSLocalizedDescriptionKey: "Unable to generate URL",
                                                 NSLocalizedFailureReasonErrorKey: localizedError]
        let error = NSError(domain: "APIError", code: 100, userInfo: userInfoDictionary)
        return error
    }()
}

extension NetworkManager {
    // MARK: - Async/Await Methods

    /// Fetch data from a URL using async/await.
    /// - Parameter url: The URL to fetch from
    /// - Returns: The response data
    /// - Throws: NSError if the request fails or returns a non-200 status code
    static func data(from url: URL, session: URLSession = .shared) async throws -> Data {
        // Check if we're running a network UI test
        if ProcessInfo.processInfo.arguments.contains("mockTimezoneDown") {
            throw internalServerError
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw internalServerError
        }

        guard httpResponse.statusCode == 200 else {
            throw internalServerError
        }

        return data
    }

    /// Fetch data from a URL path string using async/await.
    /// - Parameter path: The URL path string to fetch from
    /// - Returns: The response data
    /// - Throws: NSError if URL construction fails or the request fails
    static func data(from path: String, session: URLSession = .shared) async throws -> Data {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.count <= 2_000,
              !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 })
        else {
            throw unableToGenerateURL
        }

        guard let components = URLComponents(string: trimmed),
              let url = components.url
        else {
            throw unableToGenerateURL
        }

        return try await data(from: url, session: session)
    }

    // MARK: - Geocoding

    /// Forward-geocode an address string via the injected `GeocodingServicing`
    /// (defaults to MapKit). Capped at `GeocodingConstants.timeout`; on
    /// timeout the request is cancelled and the call throws.
    /// - Parameters:
    ///   - address: The address string to geocode
    ///   - geocoder: The geocoding service to use; injectable for tests
    /// - Returns: The first matching `GeocodedPlace`
    /// - Throws: NSError if no results are found, the request times out, or
    ///           geocoding fails
    static func geocodeAddress(_ address: String,
                               geocoder: GeocodingServicing = MapKitGeocodingService()) async throws -> GeocodedPlace {
        let places = try await geocoder.forward(addressString: address)
        guard let place = places.first else {
            throw NSError(domain: "NetworkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No results found"])
        }
        return place
    }
}
