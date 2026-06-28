// Copyright © 2026 Chris Tirpak
//
// DaybreakDefaults — additive v4 preferences that don't yet exist in the legacy schema.
//
// These are intentionally kept out of the carefully-migrated core (`Strings.swift` /
// `AppDefaults` / `DataStore`) for the duration of the redesign: each accessor reads through a
// sensible fallback, so no default-registration or migration is required to ship Phase 1. Every
// v4 key string is now centralized in `Keys` below (the single source of truth); folding the typed
// accessors into `DataStore` and registering defaults in `AppDefaults` remains a later step.

import Foundation

enum DaybreakDefaults {

    enum Keys {
        /// IANA identifier of the user's chosen Home city. Empty → Home tracks the current location
        /// (so "current == home" and the hero reads "· YOUR TIME").
        static let homeTimezoneID = "com.tpak.meridian.v4.homeTimezoneID"
        /// Days the scrubber can travel into the past (README §F; design default 2).
        static let travelPastDays = "com.tpak.meridian.v4.travelPastDays"
        /// Scrubber snap + arrow-nudge step in minutes: 5 / 15 / 30 / 60 (README §F; default 15).
        static let snapStep = "com.tpak.meridian.v4.snapStep"
        /// Pin the current-location row to the top of the list (Settings → Cities; default on).
        static let pinCurrentToTop = "com.tpak.meridian.v4.pinCurrentToTop"
        /// Popover text-scale factor 0.85–1.3 (Settings → Appearance → Text size; default 1.0).
        static let textScale = "com.tpak.meridian.v4.textScale"
        /// Show the leading color dot in the menu bar (Settings → Menu Bar; default on).
        static let menubarColorDots = "com.tpak.meridian.v4.menubarColorDots"
        /// Legacy two-line stacked menu-bar layout, opt-in via the "Stacked" preset (#142; default off).
        static let menubarStacked = "com.tpak.meridian.v4.menubarStacked"
        /// Active menu-bar density preset id (Settings → Menu Bar; default "compact").
        static let menubarPreset = "com.tpak.meridian.v4.menubarPreset"
        /// Per-city color-dot hex map, JSON-encoded (Settings → Cities).
        static let cityColors = "com.tpak.meridian.v4.cityColors"
        /// Saved top-left point of the floating popover.
        static let daybreakFloatingTopLeft = "com.tpak.meridian.v4.daybreakFloatingTopLeft"
    }

    private static var standard: UserDefaults { .standard }

    /// Home city IANA id, or `nil` if unset (→ caller falls back to current location).
    static var homeTimezoneID: String? {
        get {
            let value = standard.string(forKey: Keys.homeTimezoneID)
            return (value?.isEmpty == false) ? value : nil
        }
        set { standard.set(newValue ?? "", forKey: Keys.homeTimezoneID) }
    }

    /// Forward travel range in days. Reuses the existing symmetric range pref as the forward bound.
    static var travelForwardDays: Int {
        let value = standard.object(forKey: UserDefaultKeys.futureSliderRange) as? Int
        return clampDays(value ?? 6, min: 1, max: 30)
    }

    /// Backward travel range in days (new in v4).
    static var travelBackDays: Int {
        get {
            let value = standard.object(forKey: Keys.travelPastDays) as? Int
            return clampDays(value ?? 2, min: 0, max: 7)
        }
        set { standard.set(clampDays(newValue, min: 0, max: 7), forKey: Keys.travelPastDays) }
    }

    /// Pin the current-location row to the top of the city list (default true).
    static var pinCurrentToTop: Bool {
        get { standard.object(forKey: Keys.pinCurrentToTop) as? Bool ?? true }
        set { standard.set(newValue, forKey: Keys.pinCurrentToTop) }
    }

    /// Scrubber snap/nudge step in minutes (5/15/30/60).
    static var snapStep: Int {
        get {
            let value = standard.object(forKey: Keys.snapStep) as? Int ?? 15
            return [5, 15, 30, 60].contains(value) ? value : 15
        }
        set { standard.set(newValue, forKey: Keys.snapStep, forKeyIfValid: [5, 15, 30, 60]) }
    }

    /// The scrubber's travel window, in minutes, spanning the user's Travel forward / back **day**
    /// window (Settings → Time Travel). `DaybreakEngine.handleFraction` pins "now" to the visual
    /// centre, so the past fills the left half of the track and the future the right half regardless
    /// of how asymmetric the window is. The ruler is a decorative tick comb (no dated day labels), so
    /// a multi-day span no longer crams illegible markers — this retires the earlier fixed
    /// hour-scale interim window and connects the previously-inert day sliders.
    static var travelRangeMinutes: ClosedRange<Int> {
        DaybreakEngine.travelRange(forwardDays: travelForwardDays, backDays: travelBackDays)
    }

    private static func clampDays(_ value: Int, min lo: Int, max hi: Int) -> Int {
        Swift.min(hi, Swift.max(lo, value))
    }
}

private extension UserDefaults {
    /// Set only when the value is in the allowed set, otherwise ignore (defensive for segmented prefs).
    func set(_ value: Int, forKey key: String, forKeyIfValid allowed: [Int]) {
        if allowed.contains(value) { set(value, forKey: key) }
    }
}
