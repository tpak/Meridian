// Copyright © 2015 Abhishek Banthia

import Foundation
import CoreModelKit
@testable import Meridian

/// Mock implementation of DataStoring protocol for isolated unit tests
class MockDataStore: DataStoring {
    var storedTimezones: [Data] = []
    var preferences: [String: Any] = [:]
    var viewTypeDisplayPreferences: [ViewType: Bool] = [:]

    func timezones() -> [Data] {
        return storedTimezones
    }

    func setTimezones(_ timezones: [Data]?) {
        storedTimezones = timezones ?? []
    }

    func menubarTimezones() -> [Data]? {
        return storedTimezones.filter {
            let timezone = TimezoneData.customObject(from: $0)
            return timezone?.isFavourite == 1
        }
    }

    func shouldDisplay(_ type: ViewType) -> Bool {
        return viewTypeDisplayPreferences[type] ?? false
    }

    func retrieve(key: String) -> Any? {
        return preferences[key]
    }

    func addTimezone(_ timezone: TimezoneData) {
        guard let encodedTimezone = NSKeyedArchiver.clocker_archive(with: timezone) else {
            return
        }
        storedTimezones.append(encodedTimezone)
    }

    func removeLastTimezone() {
        if !storedTimezones.isEmpty {
            storedTimezones.removeLast()
        }
    }

    func timezoneFormat() -> NSNumber {
        return preferences[UserDefaultKeys.selectedTimeZoneFormatKey] as? NSNumber ?? NSNumber(integerLiteral: 0)
    }

    func isBufferRequiredForTwelveHourFormats() -> Bool {
        let timeFormatsWithSuffix: Set<NSNumber> = Set([
            NSNumber(integerLiteral: 0),
            NSNumber(integerLiteral: 3),
            NSNumber(integerLiteral: 4),
            NSNumber(integerLiteral: 6),
            NSNumber(integerLiteral: 7)
        ])
        return timeFormatsWithSuffix.contains(timezoneFormat())
    }

    func shouldShowDateInMenubar() -> Bool {
        return shouldDisplay(.dateInMenubar)
    }

    func shouldShowDayInMenubar() -> Bool {
        return shouldDisplay(.dayInMenubar)
    }
}
