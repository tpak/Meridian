// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLocation

/// Meridian makes no HTTP requests of its own — geocoding goes through MapKit and update checks
/// through Sparkle — so what remains here is the geocoding entry point the app actually calls.
///
/// The generic async HTTP client that used to live here (`data(from: URL)` / `data(from: String)`,
/// plus the `internalServerError` / `unableToGenerateURL` sentinels they threw) had no call site in
/// shipping code and was removed in #198. Recover it from git history if a real HTTP need appears —
/// and add an `https` scheme check when you do; the old string overload accepted any scheme.
enum NetworkManager {}

extension NetworkManager {
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
