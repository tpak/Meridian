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
    @Published var sort: SortMode = .timeDiff { didSet { reload() } }

    private let store = DataStore.shared()
    private var cancellables = Set<AnyCancellable>()

    init() {
        reload()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: Derived state

    var homeTimezoneID: String? { DaybreakDefaults.homeTimezoneID }

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
        let homeID = DaybreakDefaults.homeTimezoneID
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

        switch sort {
        case .name: built.sort { $0.region.localizedCompare($1.region) == .orderedAscending }
        case .label: built.sort { $0.label.localizedCompare($1.label) == .orderedAscending }
        case .timeDiff: break // keep stored order (already time-ordered by user)
        }

        // Pin current location to top (README/Settings "Pin to top").
        if DaybreakDefaults.pinCurrentToTop, let idx = built.firstIndex(where: { $0.isCurrent }), idx > 0 {
            let row = built.remove(at: idx)
            built.insert(row, at: 0)
        }

        rows = built
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

    func move(fromOffsets: IndexSet, toOffset: Int) {
        guard sort == .timeDiff else { return } // reordering only meaningful in manual order
        var objects = store.timezoneObjects()
        objects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist(objects)
    }

    /// Add a timezone by IANA identifier (local, no geocoding). Geocoded city search is a follow-up.
    func addTimezone(identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        let name = identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? identifier
        // Coordinates 0/0 mark "unknown" (Daybreak falls back to a default sun window); a unique
        // placeID keeps TimezoneData equality stable.
        let data = TimezoneData.make(timezoneID: identifier, name: name, customLabel: "",
                                     latitude: 0, longitude: 0, placeIdentifier: UUID().uuidString)
        store.addTimezone(data)
        reload()
    }

    /// Candidate IANA identifiers matching a query (for the add field).
    func searchTimezones(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.lowercased().contains(q) }
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
