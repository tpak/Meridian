// Copyright © 2026 Chris Tirpak
//
// CityListModel — backbone for the v4 Settings → Cities pane. Wraps the DataStore timezone list
// with SwiftUI-friendly row models and mutation helpers (favorite, label, color, remove, reorder,
// home, current-location), persisting through the single `setTimezones(_:)` write point. The other
// Settings panes bind straight to @AppStorage; only the Cities list needs this stateful model.

import Foundation
import Combine
import CoreLocation
import CoreModelKit

struct SettingsCityRow: Identifiable, Equatable {
    let id: String          // city identity (placeID ?? timezoneID)
    var timezoneID: String
    var label: String       // editable custom label (or resolved name)
    var region: String      // region/timezone descriptor
    var time: String        // live local time
    var offset: String      // offset relative to current location
    var isFavourite: Bool
    var isHome: Bool
    var isCurrent: Bool
    var colorHex: String
}

@MainActor
final class CityListModel: ObservableObject {

    enum SortMode: String, CaseIterable, Identifiable {
        case timeDiff, name, label
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timeDiff: return "Time diff"
            case .name: return "Name"
            case .label: return "Label"
            }
        }
    }

    @Published private(set) var rows: [SettingsCityRow] = []
    @Published private(set) var effectiveHomeID: String = ""
    @Published private(set) var sort: SortMode = .timeDiff
    /// When true the active sort runs in reverse (Z→A, ascending time-diff, …). Re-tapping the
    /// active sort segment flips this; choosing a different sort resets it to the default direction.
    @Published private(set) var sortReversed = false

    /// Ranked results for the "add a city" field. Local hits appear instantly; a precise geocoded
    /// city is merged in on top a moment later (see `updateSearch`).
    @Published private(set) var searchResults: [CitySearchResult] = []

    private let store = DataStore.shared()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var currentQuery = ""

    init() {
        reload()
        // Debounced: didChangeNotification fires for ANY process-wide write. reload() also diffs
        // before publishing, so unrelated writes don't churn the SwiftUI list.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: Derived state

    var homeTimezoneID: String? { DaybreakDefaults.homeTimezoneID }

    /// The home timezone the UI should reflect: the user's choice, or the current location when
    /// unset (DaybreakDefaults documents nil-home as "tracks the current location").
    private func resolvedHome(_ objects: [TimezoneData]) -> String {
        if let id = DaybreakDefaults.homeTimezoneID { return id }
        let currentID = TimeZone.current.identifier
        let match = objects.first { $0.isSystemTimezone } ?? objects.first { $0.timezone() == currentID }
        return match?.timezone() ?? currentID
    }

    private func currentLocationIdentity(_ objects: [TimezoneData]) -> String? {
        let currentID = TimeZone.current.identifier
        let match = objects.first { $0.isSystemTimezone } ?? objects.first { $0.timezone() == currentID }
        return match.map(identity)
    }

    private func identity(_ city: TimezoneData) -> String {
        if let pid = city.placeID, !pid.isEmpty { return pid }
        if let tid = city.timezoneID, !tid.isEmpty { return tid }
        return city.timezone()
    }

    // MARK: Load

    func reload() {
        let objects = store.timezoneObjects()
        let currentIdentity = currentLocationIdentity(objects)
        let homeID = resolvedHome(objects)
        let now = Date()
        let currentTZ = TimeZone.current

        var built: [SettingsCityRow] = objects.map { city in
            let tz = TimeZone(identifier: city.timezone()) ?? .current
            let ops = TimezoneDataOperations(with: city, store: store)
            let offsetMinutes = (tz.secondsFromGMT(for: now) - currentTZ.secondsFromGMT(for: now)) / 60
            let id = identity(city)
            return SettingsCityRow(
                id: id,
                timezoneID: city.timezone(),
                label: city.formattedTimezoneLabel(),
                region: city.timezone(),
                time: ops.time(with: 0),
                offset: offsetMinutes == 0 ? "Here" : DaybreakEngine.offsetLabel(offsetMinutes: offsetMinutes),
                isFavourite: city.isFavourite == 1,
                isHome: city.timezone() == homeID,
                isCurrent: id == currentIdentity,
                colorHex: CityColorStore.hex(for: id)
            )
        }

        // Stable, numeric-aware ordering with an id tiebreaker so equal keys don't shuffle on reload.
        func less(_ lhsKey: String, _ lhsID: String, _ rhsKey: String, _ rhsID: String) -> Bool {
            let c = lhsKey.localizedStandardCompare(rhsKey)
            return c == .orderedSame ? lhsID < rhsID : c == .orderedAscending
        }
        let rev = sortReversed
        switch sort {
        case .name:
            built.sort { rev ? less($1.region, $1.id, $0.region, $0.id) : less($0.region, $0.id, $1.region, $1.id) }
        case .label:
            built.sort { rev ? less($1.label, $1.id, $0.label, $0.id) : less($0.label, $0.id, $1.label, $1.id) }
        case .timeDiff: break // keep stored order (already time-ordered by applySort, incl. reversal)
        }

        // Pin current location to top (README/Settings "Pin to top").
        if DaybreakDefaults.pinCurrentToTop, let idx = built.firstIndex(where: { $0.isCurrent }), idx > 0 {
            let row = built.remove(at: idx)
            built.insert(row, at: 0)
        }

        effectiveHomeID = homeID
        if built != rows { rows = built } // diff so identical rebuilds don't churn the list
    }

    // MARK: Mutations

    func toggleFavourite(_ id: String) {
        mutate(id) { $0.isFavourite = ($0.isFavourite == 1) ? 0 : 1 }
    }

    func setLabel(_ id: String, _ text: String) {
        mutate(id) { $0.setLabel(text) }
        NotificationCenter.default.post(name: .customLabelChanged, object: nil)
    }

    func setColor(_ id: String, hex: String) {
        CityColorStore.setHex(hex, for: id)
        reload()
    }

    func setHome(timezoneID: String) {
        DaybreakDefaults.homeTimezoneID = timezoneID
        reload()
    }

    func remove(_ id: String) {
        var objects = store.timezoneObjects()
        objects.removeAll { identity($0) == id }
        persist(objects)
        NotificationCenter.default.post(name: .customLabelChanged, object: nil)
    }

    /// Reordering is only honored in manual (time-diff) order with pin-to-top OFF, because pinning
    /// makes the displayed order diverge from the stored order — applying display offsets to the
    /// stored array would corrupt it. `CitiesPane` only offers the drag affordance under the same
    /// condition (see `canReorder`).
    var canReorder: Bool { sort == .timeDiff && !DaybreakDefaults.pinCurrentToTop }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        guard canReorder else { return }
        var objects = store.timezoneObjects()
        objects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist(objects)
    }

    // MARK: Search

    /// Drive the "add a city" results. Local matches are computed synchronously and published
    /// immediately (no UserDefaults read — the installed set comes from the in-memory rows, which is
    /// what fixed the per-keystroke lag). When the local index didn't already nail the city by name,
    /// a debounced geocode fetches the precise place (correct coordinates → real sunrise/sunset) and
    /// merges it on top.
    func updateSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmed
        guard !trimmed.isEmpty else { searchResults = []; return }

        let installed = Set(rows.map { $0.timezoneID })
        let local = CitySearchService.search(trimmed, excluding: installed)
        searchResults = local.results

        // Fire the geocoder only when the local index didn't already nail the city by name. That
        // both avoids redundant lookups for direct hits AND prevents partial-word garbage: "new y"
        // is a strong prefix of New York, so we keep the local result instead of geocoding "new y"
        // into something unrelated like New Haven. Debounced so we don't geocode on every keystroke.
        guard trimmed.count >= 3, !local.hasStrongMatch else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.geocode(trimmed, installed: installed)
        }
    }

    private func geocode(_ query: String, installed: Set<String>) async {
        guard let place = try? await NetworkManager.geocodeAddress(query),
              let timezone = place.timeZone,
              currentQuery == query,                       // a newer keystroke superseded us
              !installed.contains(timezone.identifier),
              Self.geocodeMatchesQuery(place, query: query)
        else { return }

        let label = place.cityName ?? place.formattedAddress ?? timezone.identifier
        let result = CitySearchResult(
            id: "city:\(timezone.identifier):\(place.coordinate.latitude),\(place.coordinate.longitude)",
            title: place.formattedAddress ?? label,
            timezoneID: timezone.identifier,
            label: label,
            kind: .city,
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude
        )
        // Precise city on top; drop any local row that resolved to the same zone so it isn't listed
        // twice.
        var merged = searchResults.filter { $0.timezoneID != timezone.identifier }
        merged.insert(result, at: 0)
        searchResults = Array(merged.prefix(CitySearchService.maxResults))
    }

    /// Accept a geocode hit only if it actually starts with what the user typed. MapKit will happily
    /// fuzz a partial query into a tangent ("new y" → New Haven, CT); this keeps those out so a
    /// debounced lookup never replaces the right local result with an unrelated city.
    private static func geocodeMatchesQuery(_ place: GeocodedPlace, query: String) -> Bool {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        let city = (place.cityName ?? "").lowercased()
        let address = (place.formattedAddress ?? "").lowercased()
        return city.hasPrefix(needle) || address.hasPrefix(needle) || needle.hasPrefix(city) && !city.isEmpty
    }

    func clearSearch() {
        searchTask?.cancel()
        currentQuery = ""
        searchResults = []
    }

    /// Install a chosen search result. Geocoded cities carry real coordinates and a friendly label;
    /// plain timezone/UTC results leave coordinates nil so `AppDelegate.backfillMissingCoordinates`
    /// resolves them on next launch (Daybreak then gets real sunrise/sunset instead of the fallback).
    func add(_ result: CitySearchResult) {
        guard TimeZone(identifier: result.timezoneID) != nil else { return }
        guard !store.timezoneObjects().contains(where: { $0.timezone() == result.timezoneID }) else { return }

        let data = TimezoneData.make(
            timezoneID: result.timezoneID,
            name: result.kind == .city ? result.title : result.label,
            customLabel: result.kind == .city ? result.label : "",
            latitude: result.latitude ?? 0,
            longitude: result.longitude ?? 0,
            placeIdentifier: UUID().uuidString
        )
        if result.latitude == nil || result.longitude == nil {
            data.latitude = nil
            data.longitude = nil
        }
        store.addTimezone(data)
        clearSearch()
        // Re-sort by the user's chosen order so the new city lands in its proper place instead of
        // at the end. applySort sorts the stored order (so the popover matches too) and reloads;
        // for Time-diff that means by offset, for Name/Label alphabetically.
        applySort()
    }

    /// Handle a tap on a sort segment: choosing a different sort switches to it in its default
    /// direction; re-tapping the active sort reverses it (alphabetical ⇄ reverse-alphabetical, etc.).
    func selectSort(_ mode: SortMode) {
        if sort == mode {
            sortReversed.toggle()
        } else {
            sort = mode
            sortReversed = false
        }
        applySort()
    }

    /// Apply the chosen sort (and reversal) to the STORED order so the popover reflects it too (not
    /// just the Settings view), then reload.
    private func applySort() {
        var objects = store.timezoneObjects()
        let now = Date()
        let currentSecs = TimeZone.current.secondsFromGMT(for: now)
        func offsetMinutes(_ city: TimezoneData) -> Int {
            ((TimeZone(identifier: city.timezone()) ?? .current).secondsFromGMT(for: now) - currentSecs) / 60
        }
        let rev = sortReversed
        switch sort {
        case .timeDiff:
            objects.sort { rev ? offsetMinutes($0) < offsetMinutes($1) : offsetMinutes($0) > offsetMinutes($1) }
        case .name:
            objects.sort { rev ? sortLess($1.timezone(), identity($1), $0.timezone(), identity($0))
                               : sortLess($0.timezone(), identity($0), $1.timezone(), identity($1)) }
        case .label:
            objects.sort { rev ? sortLess($1.formattedTimezoneLabel(), identity($1), $0.formattedTimezoneLabel(), identity($0))
                               : sortLess($0.formattedTimezoneLabel(), identity($0), $1.formattedTimezoneLabel(), identity($1)) }
        }
        persist(objects)
    }

    private func sortLess(_ lhsKey: String, _ lhsID: String, _ rhsKey: String, _ rhsID: String) -> Bool {
        let comparison = lhsKey.localizedStandardCompare(rhsKey)
        return comparison == .orderedSame ? lhsID < rhsID : comparison == .orderedAscending
    }

    // MARK: Persistence helpers

    private func mutate(_ id: String, _ change: (TimezoneData) -> Void) {
        let objects = store.timezoneObjects()
        for object in objects where identity(object) == id { change(object) }
        persist(objects)
    }

    private func persist(_ objects: [TimezoneData]) {
        let blobs = objects.compactMap { NSKeyedArchiver.secureArchive(with: $0) }
        store.setTimezones(blobs)
        reload()
    }
}
