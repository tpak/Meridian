// Copyright © 2026 Chris Tirpak
//
// DaybreakViewModel — assembles the immutable view-data the Daybreak SwiftUI surfaces render.
//
// It owns the travel offset and a 1-second tick, reads the live timezone list + preferences from
// `DataStore`, and produces a single `DaybreakSnapshot` (so each recompute publishes once). The
// dynamic rules it encodes are from the design handoff README §A–§F; the math itself lives in the
// pure `DaybreakEngine` and the `DaybreakComputation` bridge.

import Foundation
import Combine
import CoreModelKit

// MARK: - View data

/// The hero (current-location) section. README §A/§C.
struct DaybreakHeroData: Equatable {
    var eyebrow: String          // "Denver · Current Location" (view upper-cases it)
    var time: String             // "8:17"
    var period: String           // "PM" (empty in 24h)
    var subline: String          // "↓ Sunset 8:28 PM · Sunday 12 June"
    var hoverSubline: String     // "UTC−6 · Sunday 12 June"
    var phase: DayPhase
    var localMinutes: Int        // seeds inline edit
    var isNight: Bool { phase.isNight }
}

/// One tracked city row. README §A/§B/§D.
struct DaybreakCityData: Identifiable, Equatable {
    var id: String
    var name: String
    var isHome: Bool
    var phase: DayPhase
    var time: String
    var period: String
    var offsetLabel: String      // "+11:30 · tmrw"
    var nextEventLabel: String   // "↑ Sunrise 6:46 AM"
    var hoverLabel: String       // "UTC+5:30 · Mon 13 Jun"
    var localMinutes: Int
    var isNight: Bool { phase.isNight }
}

/// A day-boundary marker under the scrubber ruler. README §F.
struct DaybreakDayMarker: Identifiable, Equatable {
    var id: Int                  // delta minutes (stable)
    var fraction: Double         // 0…1 across the track
    var label: String            // "Sun 12"
    var isToday: Bool
}

/// A single ruler tick on the scrubber track. Hour-aligned; `isMajor` marks the 6-hourly emphasis
/// ticks (06:00/12:00/18:00) that are taller and more opaque than the plain hour ticks between them.
struct DaybreakTick: Identifiable, Equatable {
    var id: Int                  // delta minutes (stable)
    var fraction: Double         // 0…1 across the track
    var isMajor: Bool
}

/// The scrubber's rendered state. README §F.
struct DaybreakScrubberData: Equatable {
    var readout: String          // "Now · 8:17 PM"
    var traveling: Bool
    var handleFraction: Double
    var handleIsNight: Bool
    var days: [DaybreakDayMarker]
    var ticks: [DaybreakTick]
}

/// A full render of the popover, published atomically.
struct DaybreakSnapshot: Equatable {
    var hero: DaybreakHeroData
    var cities: [DaybreakCityData]
    var scrubber: DaybreakScrubberData
    /// True when the current location differs from the user's Home city (drives the hero label and
    /// whether the Home row shows a ⌂ badge). README §A.
    var locationTraveling: Bool
    var versionText: String
}

// MARK: - View model

final class DaybreakViewModel: ObservableObject {

    @Published private(set) var snapshot: DaybreakSnapshot
    private(set) var travelOffsetMinutes: Int = 0
    /// IANA id of the current-location (hero) timezone; used to resolve the hero's inline time edit.
    private(set) var heroTimeZoneIdentifier: String = TimeZone.current.identifier

    private let store: DataStore
    private var now: Date
    private var ticker: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Owned formatters (main-thread; avoids the non-thread-safe shared DateFormatterManager).
    private let fullDate = DaybreakViewModel.makeFormatter("EEEE d MMMM")
    private let markerDate = DaybreakViewModel.makeFormatter("EEE d")
    private let shortWeekday = DaybreakViewModel.makeFormatter("EEE")
    private let hoverDate = DaybreakViewModel.makeFormatter("EEE d MMM")

    init(store: DataStore = .shared(), now: Date = Date()) {
        self.store = store
        self.now = now
        self.snapshot = DaybreakViewModel.emptySnapshot()
        recompute()
        observeExternalChanges()
    }

    deinit { ticker?.invalidate() }

    var travelRange: ClosedRange<Int> { DaybreakDefaults.travelRangeMinutes }
    var snapStep: Int { DaybreakDefaults.snapStep }

    // MARK: Lifecycle (panel show/hide)

    func startTicking() {
        now = Date()
        // Always open at the present moment: the hero (current location) must match the system clock.
        // Time travel is a transient, per-session exploration — it never carries over to a new open.
        travelOffsetMinutes = 0
        recompute()
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            self.recompute()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Scrubber / travel mutations

    func setOffset(_ minutes: Int) {
        let clamped = DaybreakEngine.clampAndSnap(minutes, range: travelRange, snapStep: snapStep)
        guard clamped != travelOffsetMinutes else { return }
        travelOffsetMinutes = clamped
        recompute()
    }

    func setOffsetFromFraction(_ fraction: Double) {
        setOffset(DaybreakEngine.offsetMinutes(fraction: fraction, range: travelRange))
    }

    func nudge(forward: Bool) {
        setOffset(travelOffsetMinutes + (forward ? snapStep : -snapStep))
    }

    func reset() {
        guard travelOffsetMinutes != 0 else { return }
        travelOffsetMinutes = 0
        recompute()
    }

    /// Commit an inline-edited time for a city (or the hero). README §E.
    func commitEditedTime(cityID: String, text: String) {
        guard let entered = DaybreakEngine.parseTime(text) else { return }
        let reference = referenceDate()
        let timeZone = timeZoneForCity(id: cityID) ?? .current
        let cityCurrent = DaybreakComputation.localMinutes(reference: reference, timeZone: timeZone)
        let newOffset = DaybreakEngine.offsetForEditedTime(currentDelta: travelOffsetMinutes,
                                                           enteredMinutes: entered,
                                                           cityCurrentLocalMinutes: cityCurrent,
                                                           range: travelRange,
                                                           snapStep: snapStep)
        travelOffsetMinutes = newOffset
        recompute()
    }

    func refresh() {
        now = Date()
        recompute()
    }

    // MARK: - Recompute

    private func referenceDate() -> Date {
        now.addingTimeInterval(TimeInterval(travelOffsetMinutes * 60))
    }

    private func observeExternalChanges() {
        // Debounced: UserDefaults.didChangeNotification fires for ANY process-wide write; coalesce
        // bursts. recompute() is also self-guarded (only publishes when the snapshot actually changes).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("NSSystemTimeZoneDidChangeNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DaybreakComputation.invalidate() // sunrise/sunset windows depend on the system zone
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func currentLocationCity(in cities: [TimezoneData]) -> TimezoneData? {
        let currentID = TimeZone.current.identifier
        return cities.first { $0.isSystemTimezone } ?? cities.first { $0.timezone() == currentID }
    }

    private func timeZoneForCity(id: String) -> TimeZone? {
        if id == "hero" { return TimeZone(identifier: heroTimeZoneIdentifier) }
        let cities = store.timezoneObjects()
        if let match = cities.first(where: { cityIdentity($0) == id }) {
            return TimeZone(identifier: match.timezone())
        }
        return nil
    }

    private func cityIdentity(_ city: TimezoneData) -> String {
        if let pid = city.placeID, !pid.isEmpty { return pid }
        if let tid = city.timezoneID, !tid.isEmpty { return tid }
        return city.timezone()
    }

    private func recompute() {
        let reference = referenceDate()
        let cities = store.timezoneObjects()

        // ---- Current location (hero) ----
        let currentCity = currentLocationCity(in: cities)
        let heroTZID = currentCity?.timezone() ?? TimeZone.current.identifier
        heroTimeZoneIdentifier = heroTZID
        let heroTZ = TimeZone(identifier: heroTZID) ?? .current
        let heroName = currentCity?.formattedTimezoneLabel() ?? Self.friendlyName(heroTZID)
        let heroWindow = sunWindow(for: currentCity, timeZone: heroTZ, reference: reference)
        let heroLocal = DaybreakComputation.localMinutes(reference: reference, timeZone: heroTZ)
        let heroOrdinal = DaybreakComputation.dayOrdinal(reference: reference, timeZone: heroTZ)
        let heroPhase = DaybreakEngine.phase(localMinutes: heroLocal, sunrise: heroWindow.sunrise, sunset: heroWindow.sunset)

        let homeID = DaybreakDefaults.homeTimezoneID ?? heroTZID
        let locationTraveling = homeID != heroTZID

        let hero = makeHero(name: heroName, locationTraveling: locationTraveling, timeZone: heroTZ,
                            reference: reference, localMinutes: heroLocal, window: heroWindow, phase: heroPhase)

        // ---- City rows (everything except the current-location city) ----
        // Never duplicate the hero: exclude EVERY tracked city in the current location's timezone
        // (covers a redundant system-timezone entry + an explicitly-added same-zone city).
        let rows: [DaybreakCityData] = cities.compactMap { city in
            if city.timezone() == heroTZID { return nil }
            return makeRow(city: city, reference: reference, heroTZ: heroTZ,
                           heroOrdinal: heroOrdinal, homeID: homeID)
        }

        // ---- Scrubber ----
        let scrubber = makeScrubber(heroTZ: heroTZ, heroLocalMinutes: heroLocal,
                                    heroPhase: heroPhase, heroOrdinal: heroOrdinal)

        let next = DaybreakSnapshot(hero: hero, cities: rows, scrubber: scrubber,
                                    locationTraveling: locationTraveling, versionText: Self.versionText())
        if next != snapshot { snapshot = next }
    }

    // MARK: Builders

    private func makeHero(name: String, locationTraveling: Bool, timeZone: TimeZone, reference: Date,
                          localMinutes: Int, window: SunWindow, phase: DayPhase) -> DaybreakHeroData {
        let (time, period) = formatTime(localMinutes)
        let event = DaybreakEngine.nextSunEvent(localMinutes: localMinutes, sunrise: window.sunrise, sunset: window.sunset)
        let eventString = eventLabel(event)
        let dateString = string(fullDate, reference, timeZone)
        let eyebrow = "\(name) · \(locationTraveling ? "Current Location" : "Your Time")"
        return DaybreakHeroData(
            eyebrow: eyebrow,
            time: time, period: period,
            subline: showSunriseSunset ? "\(eventString) · \(dateString)" : dateString,
            hoverSubline: "\(utcLabel(timeZone, reference)) · \(dateString)",
            phase: phase, localMinutes: localMinutes
        )
    }

    private func makeRow(city: TimezoneData, reference: Date, heroTZ: TimeZone,
                         heroOrdinal: Int, homeID: String) -> DaybreakCityData {
        let tz = TimeZone(identifier: city.timezone()) ?? .current
        let local = DaybreakComputation.localMinutes(reference: reference, timeZone: tz)
        let ordinal = DaybreakComputation.dayOrdinal(reference: reference, timeZone: tz)
        let window = sunWindow(for: city, timeZone: tz, reference: reference)
        let phase = DaybreakEngine.phase(localMinutes: local, sunrise: window.sunrise, sunset: window.sunset)
        let (time, period) = formatTime(local)

        let offsetMinutes = (tz.secondsFromGMT(for: reference) - heroTZ.secondsFromGMT(for: reference)) / 60
        var offsetLabel = DaybreakEngine.offsetLabel(offsetMinutes: offsetMinutes)
        if let tag = DaybreakEngine.dayTag(dayDelta: ordinal - heroOrdinal) {
            offsetLabel += " · \(tag)"
        }

        let event = DaybreakEngine.nextSunEvent(localMinutes: local, sunrise: window.sunrise, sunset: window.sunset)
        let hover = "\(utcLabel(tz, reference)) · \(string(hoverDate, reference, tz))"

        return DaybreakCityData(
            id: cityIdentity(city),
            name: city.formattedTimezoneLabel(),
            isHome: tz.identifier == homeID,
            phase: phase,
            time: time, period: period,
            offsetLabel: offsetLabel,
            nextEventLabel: showSunriseSunset ? eventLabel(event) : hover,
            hoverLabel: hover,
            localMinutes: local
        )
    }

    private func makeScrubber(heroTZ: TimeZone, heroLocalMinutes: Int, heroPhase: DayPhase, heroOrdinal: Int) -> DaybreakScrubberData {
        let range = travelRange
        let fraction = DaybreakEngine.handleFraction(offsetMinutes: travelOffsetMinutes, range: range)
        let readout = DaybreakEngine.readout(deltaMinutes: travelOffsetMinutes,
                                             currentLocalMinutes: heroLocalMinutes,
                                             weekdayShort: string(shortWeekday, referenceDate(), heroTZ))

        // Walk *true* local midnights of the current location within the travel range. Stepping a
        // fixed 1440 minutes would drift on DST-transition days (23/25h); `Calendar` advances days
        // correctly, so markers and labels stay pinned to real midnights.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = heroTZ
        let rangeStart = now.addingTimeInterval(TimeInterval(range.lowerBound * 60))
        let rangeEnd = now.addingTimeInterval(TimeInterval(range.upperBound * 60))
        var midnight = calendar.startOfDay(for: rangeStart)
        if midnight < rangeStart {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? rangeEnd.addingTimeInterval(1)
        }
        var markers: [DaybreakDayMarker] = []
        while midnight <= rangeEnd {
            let delta = Int((midnight.timeIntervalSince(now) / 60).rounded())
            let ordinal = DaybreakComputation.dayOrdinal(reference: midnight, timeZone: heroTZ)
            markers.append(DaybreakDayMarker(
                id: delta,
                fraction: DaybreakEngine.handleFraction(offsetMinutes: delta, range: range),
                label: string(markerDate, midnight, heroTZ),
                isToday: ordinal == heroOrdinal
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
        }

        return DaybreakScrubberData(
            readout: readout,
            traveling: travelOffsetMinutes != 0,
            handleFraction: fraction,
            handleIsNight: heroPhase.isNight,
            days: markers,
            ticks: hourTicks(calendar: calendar, rangeStart: rangeStart, rangeEnd: rangeEnd, range: range)
        )
    }

    /// Hour ruler: one tick per local clock hour, with 6-hourly ticks (06/12/18) emphasised. Midnight
    /// is skipped — the taller, labelled day marker already stands there.
    private func hourTicks(calendar: Calendar, rangeStart: Date, rangeEnd: Date,
                           range: ClosedRange<Int>) -> [DaybreakTick] {
        var ticks: [DaybreakTick] = []
        var hourMark = calendar.dateInterval(of: .hour, for: rangeStart)?.start ?? rangeStart
        if hourMark < rangeStart {
            hourMark = calendar.date(byAdding: .hour, value: 1, to: hourMark) ?? rangeEnd.addingTimeInterval(1)
        }
        while hourMark <= rangeEnd {
            let hourOfDay = calendar.component(.hour, from: hourMark)
            if hourOfDay != 0 {
                let delta = Int((hourMark.timeIntervalSince(now) / 60).rounded())
                ticks.append(DaybreakTick(
                    id: delta,
                    fraction: DaybreakEngine.handleFraction(offsetMinutes: delta, range: range),
                    isMajor: hourOfDay % 6 == 0
                ))
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hourMark) else { break }
            hourMark = next
        }
        return ticks
    }

    // MARK: Helpers

    private func sunWindow(for city: TimezoneData?, timeZone: TimeZone, reference: Date) -> SunWindow {
        guard let city else { return DaybreakComputation.fallbackSunWindow }
        return DaybreakComputation.sunWindow(reference: reference,
                                             latitude: city.latitude,
                                             longitude: city.longitude,
                                             timeZone: timeZone,
                                             timezoneID: timeZone.identifier) ?? DaybreakComputation.fallbackSunWindow
    }

    /// Settings → Appearance → "Sunrise / sunset". When off, the next-sun-event sub-labels are
    /// suppressed (rows fall back to the UTC line; the hero subline shows just the date).
    private var showSunriseSunset: Bool { store.showSunriseSunset }

    private func formatTime(_ minutes: Int) -> (time: String, period: String) {
        switch store.timeFormat {
        case .twentyFourHour, .twentyFourHourWithSeconds:
            return (DaybreakEngine.format24(minutes: minutes), "")
        case .twelveHourWithoutAmPm, .twelveHourWithoutAmPmAndSeconds:
            return (DaybreakEngine.format12(minutes: minutes).time, "")
        default:
            let r = DaybreakEngine.format12(minutes: minutes)
            return (r.time, r.period)
        }
    }

    private func eventLabel(_ event: SunEvent) -> String {
        let arrow = event.kind == .sunrise ? "↑" : "↓"
        let name = event.kind == .sunrise ? "Sunrise" : "Sunset"
        let (time, period) = formatTime(event.minutes)
        return period.isEmpty ? "\(arrow) \(name) \(time)" : "\(arrow) \(name) \(time) \(period)"
    }

    private func utcLabel(_ timeZone: TimeZone, _ reference: Date) -> String {
        let totalMinutes = timeZone.secondsFromGMT(for: reference) / 60
        let sign = totalMinutes < 0 ? DaybreakEngine.minus : "+"
        let abs = Swift.abs(totalMinutes)
        let h = abs / 60, m = abs % 60
        return m == 0 ? "UTC\(sign)\(h)" : "UTC\(sign)\(h):\(String(format: "%02d", m))"
    }

    private func string(_ formatter: DateFormatter, _ date: Date, _ timeZone: TimeZone) -> String {
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func friendlyName(_ tzID: String) -> String {
        (tzID.split(separator: "/").last.map(String.init) ?? tzID).replacingOccurrences(of: "_", with: " ")
    }

    private static func versionText() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0"
        return "v\(v)"
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.dateFormat = format
        return f
    }

    private static func emptySnapshot() -> DaybreakSnapshot {
        DaybreakSnapshot(
            hero: DaybreakHeroData(eyebrow: "", time: "", period: "", subline: "", hoverSubline: "",
                                   phase: .day, localMinutes: 0),
            cities: [],
            scrubber: DaybreakScrubberData(readout: "Now", traveling: false, handleFraction: 0.5,
                                           handleIsNight: false, days: [], ticks: []),
            locationTraveling: false,
            versionText: versionText()
        )
    }
}
