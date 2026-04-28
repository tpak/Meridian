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

// MARK: - Typed preference enums (issue #97)

enum MenubarMode: Int, Codable {
    case compact = 0
    case standard = 1
}

enum Theme: Int, Codable {
    case light = 0
    case dark = 1
    case system = 2
}

enum RelativeDateDisplay: Int, Codable {
    case relative = 0
    case actual = 1
    case date = 2
    case hidden = 3
}

enum AppPresentation: Int, Codable {
    case menubarOnly = 0
    case menubarAndDock = 1
}

// Indices match the popup item order in
// AppearanceViewController.setupTimeFormatPopup(); 2/5/8 are disabled
// separator rows and intentionally have no enum case.
enum TimeFormat: Int, Codable {
    case twelveHour = 0
    case twentyFourHour = 1
    case twelveHourWithSeconds = 3
    case twentyFourHourWithSeconds = 4
    case twelveHourWithLeadingZero = 6
    case twelveHourWithLeadingZeroAndSeconds = 7
    case twelveHourWithoutAmPm = 9
    case twelveHourWithoutAmPmAndSeconds = 10
    case epoch = 11
}

// MARK: - Typed accessors (issue #97)

// These wrap the legacy inverted/Int storage with type-safe APIs. They read
// and write the same UserDefaults keys as the existing shouldDisplay(_:)
// switch, so behavior is unchanged — they exist so callers can stop
// re-implementing the inversion at every read site. A subsequent commit
// migrates storage to native Bool / enum-rawValue keys and renames legacy
// keys; the accessors are the seam where that swap happens.
extension DataStore {
    // Inverted bools — legacy storage: 0 = show, 1 = hide.
    var showSunriseSunset: Bool {
        get {
            guard let value = userDefaults.object(forKey: UserDefaultKeys.sunriseSunsetTime) as? NSNumber else {
                return false
            }
            return value.intValue == 0
        }
        set {
            userDefaults.set(NSNumber(value: newValue ? 0 : 1), forKey: UserDefaultKeys.sunriseSunsetTime)
        }
    }

    var showFutureSlider: Bool {
        get {
            guard let value = userDefaults.object(forKey: UserDefaultKeys.displayFutureSliderKey) as? NSNumber else {
                return false
            }
            return value.intValue != 1
        }
        set {
            userDefaults.set(NSNumber(value: newValue ? 0 : 1), forKey: UserDefaultKeys.displayFutureSliderKey)
        }
    }

    var showDayInMenubar: Bool {
        get { userDefaults.integer(forKey: UserDefaultKeys.showDayInMenu) == 0 }
        set { userDefaults.set(newValue ? 0 : 1, forKey: UserDefaultKeys.showDayInMenu) }
    }

    var showDateInMenubar: Bool {
        get { userDefaults.integer(forKey: UserDefaultKeys.showDateInMenu) == 0 }
        set { userDefaults.set(newValue ? 0 : 1, forKey: UserDefaultKeys.showDateInMenu) }
    }

    var showPlaceNameInMenubar: Bool {
        get {
            guard let value = userDefaults.object(forKey: UserDefaultKeys.showPlaceInMenu) as? NSNumber else {
                return false
            }
            return value.intValue == 0
        }
        set {
            userDefaults.set(NSNumber(value: newValue ? 0 : 1), forKey: UserDefaultKeys.showPlaceInMenu)
        }
    }

    // Non-inverted bool — legacy storage: 1 = float, 0 = menubar.
    var floatOnTop: Bool {
        get { userDefaults.integer(forKey: UserDefaultKeys.showAppInForeground) == 1 }
        set { userDefaults.set(newValue ? 1 : 0, forKey: UserDefaultKeys.showAppInForeground) }
    }

    // Enums — raw int storage matches the popup/segment selectedIndex.
    var menubarMode: MenubarMode {
        get {
            guard let raw = userDefaults.object(forKey: UserDefaultKeys.menubarCompactMode) as? Int else {
                return .standard
            }
            return MenubarMode(rawValue: raw) ?? .standard
        }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.menubarCompactMode) }
    }

    var theme: Theme {
        get {
            guard let raw = userDefaults.object(forKey: UserDefaultKeys.themeKey) as? Int else {
                return .light
            }
            return Theme(rawValue: raw) ?? .light
        }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.themeKey) }
    }

    var relativeDateDisplay: RelativeDateDisplay {
        get {
            guard let raw = (userDefaults.object(forKey: UserDefaultKeys.relativeDateKey) as? NSNumber)?.intValue else {
                return .relative
            }
            return RelativeDateDisplay(rawValue: raw) ?? .relative
        }
        set {
            userDefaults.set(NSNumber(value: newValue.rawValue), forKey: UserDefaultKeys.relativeDateKey)
        }
    }

    var appPresentation: AppPresentation {
        get {
            guard let value = userDefaults.object(forKey: UserDefaultKeys.appDisplayOptions) as? NSNumber else {
                return .menubarOnly
            }
            return AppPresentation(rawValue: value.intValue) ?? .menubarOnly
        }
        set {
            userDefaults.set(NSNumber(value: newValue.rawValue), forKey: UserDefaultKeys.appDisplayOptions)
        }
    }

    var timeFormat: TimeFormat {
        get {
            guard let raw = (userDefaults.object(forKey: UserDefaultKeys.selectedTimeZoneFormatKey) as? NSNumber)?.intValue else {
                return .twelveHour
            }
            return TimeFormat(rawValue: raw) ?? .twelveHour
        }
        set {
            userDefaults.set(NSNumber(value: newValue.rawValue), forKey: UserDefaultKeys.selectedTimeZoneFormatKey)
        }
    }
}
