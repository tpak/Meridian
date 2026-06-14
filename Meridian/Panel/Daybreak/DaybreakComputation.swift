// Copyright © 2026 Chris Tirpak
//
// DaybreakComputation — bridges Foundation date/timezone math and the vendored Solar calculator
// to the integer primitives `DaybreakEngine` consumes (minutes-since-local-midnight, a comparable
// day ordinal, and a per-city sunrise/sunset window).
//
// All access is main-thread (the panel's timer + UI live on the main actor), so the small Solar
// cache needs no locking. Unlike the legacy `TimezoneDataOperations` sunrise cache — which keys on
// *today* and so never moves while scrubbing — this keys on the *reference instant's* local day, so
// a city correctly flips sun↔moon as you travel across its sunrise/sunset (README §B/§F).

import Foundation
import CoreLocation

/// A city's sunrise & sunset for a given day, in minutes since that city's local midnight.
struct SunWindow: Equatable {
    let sunrise: Int
    let sunset: Int
}

enum DaybreakComputation {

    /// Cached Solar results keyed by "<timezoneID>#<localDayOrdinal>". A `nil` value is a *cached
    /// miss* (polar day/night or missing coordinates) — distinct from "not yet computed".
    private static var solarCache: [String: SunWindow?] = [:]

    /// Minutes since local midnight (0–1439) for `reference`, rendered in `timeZone`.
    static func localMinutes(reference: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: reference)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// A timezone-independent day ordinal for `reference`'s *local* calendar date, so two cities'
    /// days can be compared for the README §A day-tag (`tmrw` / `yest.` / `+2d`). The local Y/M/D is
    /// re-pinned to a UTC midnight and divided into whole days.
    static func dayOrdinal(reference: Date, timeZone: TimeZone) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let c = local.dateComponents([.year, .month, .day], from: reference)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? timeZone
        let pinned = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? reference
        return Int((pinned.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// Sunrise/sunset window (local minutes) for a city at the reference instant, or `nil` when the
    /// city has no usable coordinates or Solar can't resolve (polar regions). Cached per local day.
    static func sunWindow(reference: Date,
                          latitude: Double?,
                          longitude: Double?,
                          timeZone: TimeZone,
                          timezoneID: String) -> SunWindow? {
        guard let lat = latitude, let lon = longitude, !(lat == 0 && lon == 0) else { return nil }

        let ordinal = dayOrdinal(reference: reference, timeZone: timeZone)
        // Key includes coordinates (rounded for stability): two cities can share a timezone
        // (e.g. New York + Atlanta) but have materially different sunrise/sunset.
        let key = "\(timezoneID)#\(ordinal)#\(round(lat * 1000))#\(round(lon * 1000))"
        if let cached = solarCache[key] { return cached } // value may itself be nil (cached miss)

        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        var window: SunWindow?
        if let solar = Solar(for: reference, coordinate: coordinate),
           let sunrise = solar.sunrise, let sunset = solar.sunset {
            window = SunWindow(sunrise: localMinutes(reference: sunrise, timeZone: timeZone),
                               sunset: localMinutes(reference: sunset, timeZone: timeZone))
        }
        if solarCache.count > 512 { solarCache.removeAll() } // bound growth across many days/cities
        solarCache[key] = window
        return window
    }

    /// A reasonable sunrise/sunset fallback (06:00 / 18:00) so phase/glyph logic still works for
    /// coordinate-less rows (e.g. a bare "UTC" timezone). README §B notes the real app should use
    /// true values where available; this keeps the visual sensible otherwise.
    static let fallbackSunWindow = SunWindow(sunrise: 6 * 60, sunset: 18 * 60)

    /// Clear the Solar cache (call when the timezone list changes, to be safe).
    static func invalidate() { solarCache.removeAll() }
}
