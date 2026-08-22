// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import CoreLocation
import Foundation
import MapKit

/// Lightweight value type carrying only the placemark fields call sites
/// actually consume. Insulates the rest of the app from MKMapItem so future
/// MapKit changes don't ripple beyond this file.
struct GeocodedPlace {
    let coordinate: CLLocationCoordinate2D
    let timeZone: TimeZone?
    let cityName: String?
    let formattedAddress: String?
    let regionCode: String?
}

/// Errors specific to GeocodingService. Network and cancellation errors from
/// MapKit pass through unchanged so existing NSError-code checks
/// (NSURLErrorNotConnectedToInternet etc.) keep working at call sites.
enum GeocodingError: LocalizedError {
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Invalid geocoding input"
        }
    }
}

enum GeocodingConstants {
    /// Cap geocoding waits at 10 seconds. Without one, a stalled network
    /// during the first-launch coordinate backfill or a city search can
    /// hang the calling Task forever.
    static let timeout: TimeInterval = 10
}

protocol GeocodingServicing: Sendable {
    func forward(addressString: String, timeout: TimeInterval) async throws -> [GeocodedPlace]
}

extension GeocodingServicing {
    func forward(addressString: String) async throws -> [GeocodedPlace] {
        try await forward(addressString: addressString, timeout: GeocodingConstants.timeout)
    }
}

struct MapKitGeocodingService: GeocodingServicing {
    func forward(addressString: String, timeout: TimeInterval) async throws -> [GeocodedPlace] {
        guard let request = MKGeocodingRequest(addressString: addressString) else {
            throw GeocodingError.invalidInput
        }
        return try await runWithTimeout(
            timeout: timeout,
            cancel: { request.cancel() },
            operation: {
                let mapItems = try await request.mapItems
                return mapItems.map(GeocodedPlace.init(mapItem:))
            }
        )
    }

}

extension GeocodedPlace {
    init(mapItem: MKMapItem) {
        let representations = mapItem.addressRepresentations
        self.coordinate = mapItem.location.coordinate
        self.timeZone = mapItem.timeZone as TimeZone?
        self.cityName = representations?.cityName
        // Full city + region + country (e.g. "Cupertino, CA, United States"),
        // falling back to MKAddress.fullAddress, then mapItem.name. Matches
        // the legacy CLPlacemark.formattedAddress shape that callers display.
        self.formattedAddress = representations?.cityWithContext(.full)
            ?? mapItem.address?.fullAddress
            ?? mapItem.name
        self.regionCode = representations?.region?.identifier
    }
}

private func runWithTimeout<T: Sendable>(
    timeout: TimeInterval,
    cancel: @escaping @Sendable () -> Void,
    operation: @Sendable () async throws -> T
) async throws -> T {
    let timeoutTask = Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        if !Task.isCancelled {
            cancel()
        }
    }
    defer { timeoutTask.cancel() }
    return try await operation()
}
