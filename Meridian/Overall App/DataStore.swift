// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

enum ViewType {
    case futureSlider
    case twelveHour
    case sunrise
    case showAppInForeground
    case appDisplayOptions
    case dateInMenubar
    case placeInMenubar
    case dayInMenubar
    case menubarCompactMode
}

protocol DataStoring: AnyObject {
    func timezones() -> [Data]
    func setTimezones(_ timezones: [Data]?)
    func menubarTimezones() -> [Data]
    func timezoneObjects() -> [TimezoneData]
    func menubarTimezoneObjects() -> [TimezoneData]
    func shouldDisplay(_ type: ViewType) -> Bool
    func retrieve(key: String) -> Any?
    func addTimezone(_ timezone: TimezoneData)
    func removeLastTimezone()
    func timezoneFormat() -> NSNumber
    func isBufferRequiredForTwelveHourFormats() -> Bool
    func shouldShowDateInMenubar() -> Bool
    func shouldShowDayInMenubar() -> Bool
}

class DataStore: NSObject, DataStoring {
    private static var sharedStore = DataStore(with: UserDefaults.standard)
    private var userDefaults: UserDefaults!
    private var cachedTimezones: [Data]
    private var cachedMenubarTimezones: [Data]
    private var cachedTimezoneObjects: [TimezoneData]
    private var cachedMenubarTimezoneObjects: [TimezoneData]
    private static let timeFormatsWithSuffix: Set<NSNumber> = Set([NSNumber(value: 0),
                                                                   NSNumber(value: 3),
                                                                   NSNumber(value: 4),
                                                                   NSNumber(value: 6),
                                                                   NSNumber(value: 7)])

    class func shared() -> DataStore {
        return sharedStore
    }

    init(with defaults: UserDefaults) {
        cachedTimezones = (defaults.object(forKey: UserDefaultKeys.defaultPreferenceKey) as? [Data]) ?? []
        cachedMenubarTimezones = cachedTimezones.filter {
            let customTimezone = TimezoneData.customObject(from: $0)
            return customTimezone?.isFavourite == 1
        }
        cachedTimezoneObjects = cachedTimezones.compactMap { TimezoneData.customObject(from: $0) }
        cachedMenubarTimezoneObjects = cachedMenubarTimezones.compactMap { TimezoneData.customObject(from: $0) }
        userDefaults = defaults
        super.init()
    }

    func timezones() -> [Data] {
        return cachedTimezones
    }

    func setTimezones(_ timezones: [Data]?) {
        userDefaults.set(timezones, forKey: UserDefaultKeys.defaultPreferenceKey)
        cachedTimezones = timezones ?? []
        cachedMenubarTimezones = cachedTimezones.filter {
            let customTimezone = TimezoneData.customObject(from: $0)
            return customTimezone?.isFavourite == 1
        }
        cachedTimezoneObjects = cachedTimezones.compactMap { TimezoneData.customObject(from: $0) }
        cachedMenubarTimezoneObjects = cachedMenubarTimezones.compactMap { TimezoneData.customObject(from: $0) }
    }

    func menubarTimezones() -> [Data] {
        return cachedMenubarTimezones
    }

    func timezoneObjects() -> [TimezoneData] {
        return cachedTimezoneObjects
    }

    func menubarTimezoneObjects() -> [TimezoneData] {
        return cachedMenubarTimezoneObjects
    }

    // MARK: Date (May 8th) in Compact Menubar

    func shouldShowDateInMenubar() -> Bool {
        return shouldDisplay(.dateInMenubar)
    }

    // MARK: Day (Sun, Mon etc.) in Compact Menubar

    func shouldShowDayInMenubar() -> Bool {
        return shouldDisplay(.dayInMenubar)
    }

    func retrieve(key: String) -> Any? {
        return userDefaults.object(forKey: key)
    }

    func addTimezone(_ timezone: TimezoneData) {
        guard let encodedTimezone = NSKeyedArchiver.secureArchive(with: timezone) else {
            return
        }

        var defaults: [Data] = timezones()
        defaults.append(encodedTimezone)
        setTimezones(defaults)
    }

    func removeLastTimezone() {
        var currentLineup = timezones()

        if currentLineup.isEmpty {
            return
        }

        currentLineup.removeLast()

        Logger.debug("Undo Action Executed")

        setTimezones(currentLineup)
    }

    func timezoneFormat() -> NSNumber {
        return userDefaults.object(forKey: UserDefaultKeys.selectedTimeZoneFormatKey) as? NSNumber ?? NSNumber(value: 0)
    }

    func isBufferRequiredForTwelveHourFormats() -> Bool {
        return DataStore.timeFormatsWithSuffix.contains(timezoneFormat())
    }

    func shouldDisplay(_ type: ViewType) -> Bool {
        switch type {
        case .futureSlider:
            let hidden = 1
            return (retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber).map { $0.intValue != hidden } ?? false
        case .twelveHour:
            return shouldDisplayHelper(UserDefaultKeys.selectedTimeZoneFormatKey)
        case .sunrise:
            return shouldDisplayHelper(UserDefaultKeys.sunriseSunsetTime)
        case .showAppInForeground:
            return userDefaults.integer(forKey: UserDefaultKeys.showAppInForeground) == 1
        case .dateInMenubar:
            return shouldDisplayNonObjectHelper(UserDefaultKeys.showDateInMenu)
        case .placeInMenubar:
            return shouldDisplayHelper(UserDefaultKeys.showPlaceInMenu)
        case .dayInMenubar:
            return shouldDisplayNonObjectHelper(UserDefaultKeys.showDayInMenu)
        case .appDisplayOptions:
            return shouldDisplayHelper(UserDefaultKeys.appDisplayOptions)
        case .menubarCompactMode:
            return (retrieve(key: UserDefaultKeys.menubarCompactMode) as? Int) == 0
        }
    }

    // MARK: Private

    private func shouldDisplayHelper(_ key: String) -> Bool {
        guard let value = retrieve(key: key) as? NSNumber else {
            return false
        }
        return value.isEqual(to: NSNumber(value: 0))
    }

    // MARK: Some values are stored as plain integers; objectForKey: will return nil, so using integerForKey:

    private func shouldDisplayNonObjectHelper(_ key: String) -> Bool {
        let value = userDefaults.integer(forKey: key)
        return value == 0
    }
}
