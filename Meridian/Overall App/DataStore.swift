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
        return NSNumber(value: timeFormat.rawValue)
    }

    func isBufferRequiredForTwelveHourFormats() -> Bool {
        return DataStore.timeFormatsWithSuffix.contains(timezoneFormat())
    }

    // shouldDisplay(_:) is the legacy entry point — kept for source-compat
    // with call sites we haven't swept yet (see commit 3/5 of issue #97). It
    // now delegates to the typed accessors so the underlying storage details
    // live in exactly one place.
    func shouldDisplay(_ type: ViewType) -> Bool {
        switch type {
        case .futureSlider:        return showFutureSlider
        case .twelveHour:          return timeFormat == .twelveHour
        case .sunrise:             return showSunriseSunset
        case .showAppInForeground: return floatOnTop
        case .dateInMenubar:       return showDateInMenubar
        case .placeInMenubar:      return showPlaceNameInMenubar
        case .dayInMenubar:        return showDayInMenubar
        case .appDisplayOptions:   return appPresentation == .menubarOnly
        case .menubarCompactMode:  return menubarMode == .compact
        }
    }
}

// MARK: - Typed preference enums (issue #97)

enum MenubarMode: Int, Codable, CaseIterable {
    case compact = 0
    case standard = 1
}

enum Theme: Int, Codable, CaseIterable {
    case light = 0
    case dark = 1
    case system = 2
}

enum RelativeDateDisplay: Int, Codable, CaseIterable {
    case relative = 0
    case actual = 1
    case date = 2
    case hidden = 3
}

enum AppPresentation: Int, Codable, CaseIterable {
    case menubarOnly = 0
    case menubarAndDock = 1
}

// Indices match the popup item order in
// AppearanceViewController.setupTimeFormatPopup(); 2/5/8 are disabled
// separator rows and intentionally have no enum case.
enum TimeFormat: Int, Codable, CaseIterable {
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

// Stable string name for typed preference enums. Used by SettingsManager v2
// JSON export ("compact" instead of 0). Names are derived from the Swift
// case identifier — keep them stable across releases since users' export
// files persist them.
extension MenubarMode { var jsonName: String { String(describing: self) } }
extension Theme { var jsonName: String { String(describing: self) } }
extension RelativeDateDisplay { var jsonName: String { String(describing: self) } }
extension AppPresentation { var jsonName: String { String(describing: self) } }
extension TimeFormat { var jsonName: String { String(describing: self) } }

extension MenubarMode {
    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.jsonName == jsonName }) else { return nil }
        self = match
    }
}
extension Theme {
    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.jsonName == jsonName }) else { return nil }
        self = match
    }
}
extension RelativeDateDisplay {
    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.jsonName == jsonName }) else { return nil }
        self = match
    }
}
extension AppPresentation {
    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.jsonName == jsonName }) else { return nil }
        self = match
    }
}
extension TimeFormat {
    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.jsonName == jsonName }) else { return nil }
        self = match
    }
}

// MARK: - Typed accessors (issue #97)

// Type-safe preference surface backed by modernized UserDefaults keys.
// Storage was migrated from the legacy inverted-bool / int-encoded keys by
// AppDefaults.runBoolSemanticsMigration on first launch of the modernized
// build. Defaults for missing keys come from AppDefaults.defaultsDictionary.
extension DataStore {
    // Bools.
    var showSunriseSunset: Bool {
        get { userDefaults.bool(forKey: UserDefaultKeys.showSunriseSunset) }
        set { userDefaults.set(newValue, forKey: UserDefaultKeys.showSunriseSunset) }
    }

    var showFutureSlider: Bool {
        get { userDefaults.bool(forKey: UserDefaultKeys.showFutureSlider) }
        set { userDefaults.set(newValue, forKey: UserDefaultKeys.showFutureSlider) }
    }

    var showDayInMenubar: Bool {
        get { userDefaults.bool(forKey: UserDefaultKeys.showDayInMenubar) }
        set { userDefaults.set(newValue, forKey: UserDefaultKeys.showDayInMenubar) }
    }

    var showDateInMenubar: Bool {
        get { userDefaults.bool(forKey: UserDefaultKeys.showDateInMenubar) }
        set { userDefaults.set(newValue, forKey: UserDefaultKeys.showDateInMenubar) }
    }

    var showPlaceNameInMenubar: Bool {
        get { userDefaults.bool(forKey: UserDefaultKeys.showPlaceNameInMenubar) }
        set { userDefaults.set(newValue, forKey: UserDefaultKeys.showPlaceNameInMenubar) }
    }

    var floatOnTop: Bool {
        get { userDefaults.bool(forKey: UserDefaultKeys.floatOnTop) }
        set { userDefaults.set(newValue, forKey: UserDefaultKeys.floatOnTop) }
    }

    // Enums (Int-backed; raw values match the popup/segment selectedIndex).
    var menubarMode: MenubarMode {
        get { MenubarMode(rawValue: userDefaults.integer(forKey: UserDefaultKeys.menubarCompactMode)) ?? .standard }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.menubarCompactMode) }
    }

    var theme: Theme {
        get { Theme(rawValue: userDefaults.integer(forKey: UserDefaultKeys.themeKey)) ?? .light }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.themeKey) }
    }

    var relativeDateDisplay: RelativeDateDisplay {
        get { RelativeDateDisplay(rawValue: userDefaults.integer(forKey: UserDefaultKeys.relativeDateKey)) ?? .relative }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.relativeDateKey) }
    }

    var appPresentation: AppPresentation {
        get { AppPresentation(rawValue: userDefaults.integer(forKey: UserDefaultKeys.appDisplayOptions)) ?? .menubarOnly }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.appDisplayOptions) }
    }

    var timeFormat: TimeFormat {
        get { TimeFormat(rawValue: userDefaults.integer(forKey: UserDefaultKeys.timeFormat)) ?? .twelveHour }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.timeFormat) }
    }
}
