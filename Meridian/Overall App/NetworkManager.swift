// Copyright © 2015 Abhishek Banthia

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
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedPath)
        else {
            throw unableToGenerateURL
        }

        return try await data(from: url, session: session)
    }

    // MARK: - Geocoding

    /// Geocode an address string using Apple's CLGeocoder.
    /// - Parameter address: The address string to geocode
    /// - Returns: The first matching CLPlacemark
    /// - Throws: NSError if no results are found or geocoding fails
    static func geocodeAddress(_ address: String) async throws -> CLPlacemark {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(address)
        guard let placemark = placemarks.first else {
            throw NSError(domain: "NetworkManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No results found"])
        }
        return placemark
    }
}
