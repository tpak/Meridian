// Copyright © 2026 Chris Tirpak
//
// DaybreakEngine — pure, dependency-free port of the v4 "Daybreak" design logic.
//
// This is a faithful Swift translation of the math in the design prototype
// (`design_handoff_meridian_v4/Meridian - Daybreak.dc.html`, class `Component`) and the
// rules spelled out in that folder's README §A–§F. It is intentionally free of Foundation
// date math, AppKit, and SwiftUI so it can be unit-tested in isolation. The view layer feeds
// it primitives (minutes-since-local-midnight, sunrise/sunset minutes, calendar-day deltas)
// and renders the strings/enums it returns.
//
// "Port the logic, don't reinvent it." — handoff README.

import Foundation

// Terse single-letter names and RGB tuples are intentional in this math-only port of the design's
// reference logic — they mirror the spec/prototype and read clearly in context.
// swiftlint:disable identifier_name large_tuple

/// Day/night phase of a city. Drives every visual: glyph (sun/moon), hero sky gradient,
/// row tint, scrubber handle. README §B.
enum DayPhase: String, Equatable {
    case night
    case dawn
    case day
    case dusk

    /// Glyph rule (README §B): only `.night` shows the moon; everything else shows the sun.
    var isNight: Bool { self == .night }
}

/// The next upcoming sunrise/sunset for a city. README §B "Next sun event".
struct SunEvent: Equatable {
    enum Kind: String, Equatable { case sunrise, sunset }
    let kind: Kind
    /// Minutes since local midnight (0–1439) of the event.
    let minutes: Int
}

enum DaybreakEngine {

    /// Unicode MINUS SIGN (U+2212), used for negative offsets/readouts to match design fidelity
    /// (the prototype uses "−", not an ASCII hyphen "-").
    static let minus = "\u{2212}"

    /// ±twilight window, in minutes, around sunrise/sunset (README §B: "the 50 = a ±50-minute
    /// twilight window").
    static let twilightWindow = 50

    // MARK: - Phase (README §B)

    /// Classify a city's local time into a `DayPhase`.
    ///
    /// ```
    /// if lm < sr - 50  OR  lm >= ss + 50 : night
    /// else if lm < sr + 50 :               dawn
    /// else if lm >= ss - 50 :              dusk
    /// else :                               day
    /// ```
    static func phase(localMinutes lm: Int, sunrise sr: Int, sunset ss: Int) -> DayPhase {
        let w = twilightWindow
        if lm < sr - w || lm >= ss + w { return .night }
        if lm < sr + w { return .dawn }
        if lm >= ss - w { return .dusk }
        return .day
    }

    /// The next sun event for the row's "↑ Sunrise / ↓ Sunset" sub-label (README §B):
    /// `if lm < sr → sunrise; else if lm < ss → sunset; else → sunrise (next day)`.
    static func nextSunEvent(localMinutes lm: Int, sunrise sr: Int, sunset ss: Int) -> SunEvent {
        if lm < sr { return SunEvent(kind: .sunrise, minutes: sr) }
        if lm < ss { return SunEvent(kind: .sunset, minutes: ss) }
        return SunEvent(kind: .sunrise, minutes: sr)
    }

    // MARK: - Time formatting

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Normalize an arbitrary minute count into 0–1439.
    static func wrapMinutes(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    /// 12-hour rendering: `("8:17", "PM")`. Mirrors the prototype `fmt12`.
    static func format12(minutes: Int) -> (time: String, period: String) {
        let m = wrapMinutes(minutes)
        let h = m / 60
        let min = m % 60
        let period = h < 12 ? "AM" : "PM"
        var hh = h % 12
        if hh == 0 { hh = 12 }
        return ("\(hh):\(pad(min))", period)
    }

    /// 24-hour rendering: `"20:17"`.
    static func format24(minutes: Int) -> String {
        let m = wrapMinutes(minutes)
        return "\(pad(m / 60)):\(pad(m % 60))"
    }

    // MARK: - Offsets (README §A)

    /// Offset label relative to the current location: `"+11:30"`, `"−4:30"`, or `"Your time"`
    /// for the hero (offset 0). Mirrors the prototype `offStr`.
    static func offsetLabel(offsetMinutes o: Int) -> String {
        if o == 0 { return String(localized: "Your time") }
        let sign = o < 0 ? minus : "+"
        let a = abs(o)
        return "\(sign)\(a / 60):\(pad(a % 60))"
    }

    /// Day tag appended when a row's calendar day differs from the hero's (README §A):
    /// `tmrw`, `yest.`, `+2d`, `2d ago`. Returns `nil` when on the same day.
    ///
    /// - Parameter dayDelta: `rowDayIndex − heroDayIndex`.
    static func dayTag(dayDelta: Int) -> String? {
        if dayDelta == 0 { return nil }
        if dayDelta < 0 {
            let k = -dayDelta
            return k == 1 ? String(localized: "yest.") : String(localized: "\(k)d ago")
        }
        return dayDelta == 1 ? String(localized: "tmrw") : String(localized: "+\(dayDelta)d")
    }

    // MARK: - Scrubber readout (README §F)

    /// Human delta for the readout pill, e.g. `"Now"`, `"+12:00"`, `"−1:30"`, `"+2d"`, `"+2d 8:00"`.
    /// Mirrors the prototype `dl(d)`.
    static func deltaLabel(deltaMinutes d: Int) -> String {
        if d == 0 { return String(localized: "Now") }
        let sign = d < 0 ? minus : "+"
        let a = abs(d)
        let days = a / 1440
        let rem = a % 1440
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if rem > 0 || days == 0 { parts.append("\(rem / 60):\(pad(rem % 60))") }
        return sign + parts.joined(separator: " ")
    }

    /// Full readout pill text (README §F): `"Now · 8:17 PM"` or `"+2d · Wed 8:17 PM"`.
    ///
    /// - Parameters:
    ///   - deltaMinutes: travel offset in minutes.
    ///   - currentLocalMinutes: the current location's local time at the traveled instant.
    ///   - weekdayShort: short weekday of the traveled instant (only shown when traveling).
    static func readout(deltaMinutes d: Int, currentLocalMinutes lm: Int, weekdayShort: String) -> String {
        let t = format12(minutes: lm)
        if d == 0 {
            return "\(String(localized: "Now")) · \(t.time) \(t.period)"
        }
        return "\(deltaLabel(deltaMinutes: d)) · \(weekdayShort) \(t.time) \(t.period)"
    }

    // MARK: - Time parser (README §E)

    /// Compiled once: `^(\d{1,2})(:(\d{2}))?\s*([ap]\.?m?\.?)?$` (optional — `try?` keeps us clear of
    /// the project's force_try ban; a compile-time-constant pattern won't actually fail).
    private static let timeRegex = try? NSRegularExpression(
        pattern: "^([0-9]{1,2})(?::([0-9]{2}))?\\s*([ap]\\.?m?\\.?)?$", options: []
    )

    /// Parse a user-entered time into minutes since midnight, or `nil` if unparseable.
    /// Accepts `3:30 PM`, `15:30`, `3pm`, `3`, `12:00 AM`, etc. (README §E lists 24h support, so
    /// this is intentionally a touch more lenient than the prototype regex, which required am/pm).
    static func parseTime(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let regex = timeRegex,
              let match = regex.firstMatch(in: s, options: [], range: range) else { return nil }

        func group(_ i: Int) -> String? {
            let r = match.range(at: i)
            guard r.location != NSNotFound, let rr = Range(r, in: s) else { return nil }
            return String(s[rr])
        }

        guard let hStr = group(1), var h = Int(hStr) else { return nil }
        let mm = group(2).flatMap { Int($0) } ?? 0
        if mm > 59 { return nil }

        let apToken = group(3)
        let meridiem: Character? = (apToken?.isEmpty == false) ? apToken?.first : nil

        if let ap = meridiem {
            // 12-hour semantics.
            if h < 1 || h > 12 { return nil }
            if ap == "p", h < 12 { h += 12 }
            if ap == "a", h == 12 { h = 0 }
        } else {
            // 24-hour semantics.
            if h > 23 { return nil }
        }
        return h * 60 + mm
    }

    // MARK: - Commit edited time (README §E)

    /// New travel offset after the user types a time into a city (README §E):
    /// `delta += enteredLocalMinutes − thatCityCurrentLocalMinutes`, then clamp + snap.
    static func offsetForEditedTime(currentDelta: Int,
                                    enteredMinutes: Int,
                                    cityCurrentLocalMinutes: Int,
                                    range: ClosedRange<Int>,
                                    snapStep: Int) -> Int {
        let raw = currentDelta + (enteredMinutes - cityCurrentLocalMinutes)
        return clampAndSnap(raw, range: range, snapStep: snapStep)
    }

    /// Clamp a delta into `range` then snap to the nearest `snapStep` minutes (README §E/§F).
    static func clampAndSnap(_ value: Int, range: ClosedRange<Int>, snapStep: Int) -> Int {
        let step = max(1, snapStep)
        let snapped = Int((Double(value) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    /// The scrubber's travel window, in minutes, derived from the user's Travel forward / back **day**
    /// settings (Settings → Time Travel). "Now" (0) is always inside the range; the past is negative,
    /// the future positive. With `backDays == 0` the range starts at 0 (travel-back disabled). README
    /// §F — the day-window scrubber that the fixed hour-scale interim window replaces.
    static func travelRange(forwardDays: Int, backDays: Int) -> ClosedRange<Int> {
        let minutesPerDay = 24 * 60
        let forward = max(0, forwardDays) * minutesPerDay
        let back = -max(0, backDays) * minutesPerDay
        return back...forward
    }

    // MARK: - Sky-color ramp (README Design Tokens)

    /// Hour-of-day → RGB stops for the piecewise-linear sky ramp.
    /// `0→(27,33,56) … 12→(166,196,226) … 24→(27,33,56)`.
    static let skyStops: [(hour: Double, rgb: (Int, Int, Int))] = [
        (0, (27, 33, 56)), (5, (27, 33, 56)), (6, (44, 40, 74)), (6.8, (120, 96, 120)),
        (7.6, (178, 150, 150)), (9, (150, 178, 210)), (12, (166, 196, 226)), (15, (150, 178, 210)),
        (16.5, (184, 160, 150)), (18.2, (178, 120, 116)), (19.6, (110, 90, 124)), (21, (48, 46, 80)),
        (22.5, (27, 33, 56)), (24, (27, 33, 56))
    ]

    /// Interpolated sky color for an hour-of-day (0–24, wraps). Mirrors the prototype `skyColor`.
    static func skyColor(hour: Double) -> (r: Int, g: Int, b: Int) {
        let h = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        let s = skyStops
        for i in 0..<(s.count - 1) {
            let a = s[i]
            let b = s[i + 1]
            if h >= a.hour && h <= b.hour {
                let f = (b.hour == a.hour) ? 0 : (h - a.hour) / (b.hour - a.hour)
                func lerp(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * f).rounded()) }
                return (lerp(a.rgb.0, b.rgb.0), lerp(a.rgb.1, b.rgb.1), lerp(a.rgb.2, b.rgb.2))
            }
        }
        let first = s[0].rgb
        return (first.0, first.1, first.2)
    }
}
