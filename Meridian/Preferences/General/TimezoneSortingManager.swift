// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreModelKit

/// Unified sorting logic for timezone lists. Replaces 4 duplicate sort
/// implementations in PreferencesViewController.
class TimezoneSortingManager {
    enum SortType {
        case time
        case label
        case name
    }

    private var ascendingByTime = false
    private var ascendingByLabel = false
    private var ascendingByName = false

    /// Sort the given timezone data by the specified type, toggling the sort direction.
    /// Returns the sorted data and the appropriate sort indicator image.
    func sort(_ timezones: [Data], by type: SortType) -> (sorted: [Data], indicatorImage: NSImage?) {
        let ascending: Bool
        switch type {
        case .time: ascending = ascendingByTime
        case .label: ascending = ascendingByLabel
        case .name: ascending = ascendingByName
        }

        let sorted = timezones.sorted { obj1, obj2 in
            guard let object1 = TimezoneData.customObject(from: obj1),
                  let object2 = TimezoneData.customObject(from: obj2)
            else {
                return false
            }
            return compare(object1, object2, by: type, ascending: ascending)
        }

        let image = ascending
            ? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Descending")
            : NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Ascending")

        // Toggle direction for next call
        switch type {
        case .time: ascendingByTime.toggle()
        case .label: ascendingByLabel.toggle()
        case .name: ascendingByName.toggle()
        }

        return (sorted, image)
    }

    /// Sort by a table column identifier (used for column header click sorting).
    /// Returns the sorted data, indicator image, and whether ascending.
    func sort(_ timezones: [Data], byColumn identifier: String, ascending: inout Bool) -> (sorted: [Data], indicatorImage: NSImage?) {
        let sorted = timezones.sorted { obj1, obj2 in
            guard let object1 = TimezoneData.customObject(from: obj1),
                  let object2 = TimezoneData.customObject(from: obj2)
            else {
                return false
            }

            if identifier == "formattedAddress" {
                let addr1 = object1.formattedAddress ?? ""
                let addr2 = object2.formattedAddress ?? ""
                return ascending ? addr1 > addr2 : addr1 < addr2
            } else {
                let label1 = object1.customLabel ?? ""
                let label2 = object2.customLabel ?? ""
                return ascending ? label1 > label2 : label1 < label2
            }
        }

        let image = ascending
            ? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Descending")
            : NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Ascending")

        ascending.toggle()

        return (sorted, image)
    }

    private func compare(_ lhs: TimezoneData, _ rhs: TimezoneData, by type: SortType, ascending: Bool) -> Bool {
        switch type {
        case .time:
            let system = NSTimeZone.system
            let tz1 = NSTimeZone(name: lhs.timezone())
            let tz2 = NSTimeZone(name: rhs.timezone())
            let diff1 = system.secondsFromGMT() - (tz1?.secondsFromGMT ?? 0)
            let diff2 = system.secondsFromGMT() - (tz2?.secondsFromGMT ?? 0)
            return ascending ? diff1 > diff2 : diff1 < diff2

        case .label:
            let label1 = lhs.customLabel ?? ""
            let label2 = rhs.customLabel ?? ""
            return ascending ? label1 > label2 : label1 < label2

        case .name:
            let addr1 = lhs.formattedAddress ?? ""
            let addr2 = rhs.formattedAddress ?? ""
            return ascending ? addr1 > addr2 : addr1 < addr2
        }
    }
}
