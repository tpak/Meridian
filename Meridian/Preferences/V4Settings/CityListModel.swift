// Copyright © 2026 Chris Tirpak
//
// CityListModel — backbone for the v4 Settings → Cities pane. Wraps the DataStore timezone list
// with SwiftUI-friendly row models and mutation helpers (favorite, label, color, remove, reorder,
// home, current-location), persisting through the single `setTimezones(_:)` write point. The other
// Settings panes bind straight to @AppStorage; only the Cities list needs this stateful model.

import Foundation
import Combine
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
    @Published var sort: SortMode = .timeDiff { didSet { reload() } }

    private let store = DataStore.shared()
    private var cancellables = Set<AnyCancellable>()

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
        switch sort {
        case .name: built.sort { less($0.region, $0.id, $1.region, $1.id) }
        case .label: built.sort { less($0.label, $0.id, $1.label, $1.id) }
        case .timeDiff: break // keep stored order (already time-ordered by user)
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

    /// Add a timezone by IANA identifier (local, no geocoding). Geocoded city search is a follow-up.
    func addTimezone(identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        // Don't add a duplicate of a timezone already tracked.
        guard !store.timezoneObjects().contains(where: { $0.timezone() == identifier }) else { return }
        let name = identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? identifier
        // Coordinates 0/0 mark "unknown" (Daybreak falls back to a default sun window); a unique
        // placeID keeps TimezoneData equality stable.
        let data = TimezoneData.make(timezoneID: identifier, name: name, customLabel: "",
                                     latitude: 0, longitude: 0, placeIdentifier: UUID().uuidString)
        store.addTimezone(data)
        reload()
    }

    /// Candidate IANA identifiers matching a query (for the add field), excluding already-tracked ones.
    func searchTimezones(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let existing = Set(store.timezoneObjects().map { $0.timezone() })
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.lowercased().contains(q) && !existing.contains($0) }
            .prefix(20)
            .map { $0 }
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
