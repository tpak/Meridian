// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

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

// Conforming `CaseIterable` enums get a stable string identifier (`jsonName`,
// defaulting to the Swift case name) for SettingsManager export/import, plus
// a failable `init?(jsonName:)` for the inverse lookup. Override `jsonName`
// when the enum's stable identifier needs to differ from the case name.
protocol JSONNameDecodable: CaseIterable {
    var jsonName: String { get }
}

extension JSONNameDecodable {
    var jsonName: String { String(describing: self) }

    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.jsonName == jsonName }) else { return nil }
        self = match
    }
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
        }
    }
}

// MARK: - Typed preference enums (issue #97)

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

// F1 team accent color. Stable string raw values are used both as the
// UserDefaults storage value and as the SettingsManager v2 export jsonName.
// Rename a case at your peril — existing exported settings files persist
// the old raw values.
//
// Hex codes sourced from infysia.com (March 2026 update). Two substitutions:
// Haas (#FFFFFF white) and Cadillac (#111111 near-black) are unusable as
// accent colors at one appearance — we substitute Haas livery red and a
// Cadillac-brand gold, respectively.
enum TeamAccent: String, Codable, CaseIterable {
    case alpine
    case astonMartin
    case audi
    case cadillac
    case ferrari
    case haas
    case mclaren
    case mercedes
    case racingBulls
    case redBull
    case williams

    static let `default`: TeamAccent = .astonMartin

    var displayName: String {
        switch self {
        case .alpine:       return "Alpine"
        case .astonMartin:  return "Aston Martin"
        case .audi:         return "Audi"
        case .cadillac:     return "Cadillac"
        case .ferrari:      return "Ferrari"
        case .haas:         return "Haas"
        case .mclaren:      return "McLaren"
        case .mercedes:     return "Mercedes"
        case .racingBulls:  return "Racing Bulls"
        case .redBull:      return "Red Bull Racing"
        case .williams:     return "Williams"
        }
    }

    private var hex: String {
        switch self {
        case .alpine:       return "0090FF"
        case .astonMartin:  return "006F62"
        case .audi:         return "C00000"
        case .cadillac:     return "DCA62E"
        case .ferrari:      return "DC0000"
        case .haas:         return "ED1C24"
        case .mclaren:      return "FF8000"
        case .mercedes:     return "00D2BE"
        case .racingBulls:  return "2647D8"
        case .redBull:      return "1E5BC6"
        case .williams:     return "005AFF"
        }
    }

    /// Resolved accent color used across the Daybreak panel and menu bar.
    /// Alpha 0.85 matches the toned-down Aston Martin shipping value (PR
    /// e4ad82b2) so saturation feels consistent across teams.
    var accentColor: NSColor {
        let h = hex
        let red = CGFloat(Int(h.prefix(2), radix: 16) ?? 0) / 255.0
        let green = CGFloat(Int(h.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
        let blue = CGFloat(Int(h.suffix(2), radix: 16) ?? 0) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 0.85)
    }

    // Override the JSONNameDecodable default (`String(describing: self)`) to
    // explicitly use rawValue. Functionally equivalent today since cases have
    // no explicit raw values, but the override locks in stability if a case
    // ever needs an explicit raw value that diverges from the case name.
    var jsonName: String { rawValue }
}

extension TeamAccent: JSONNameDecodable {}

// The team-accent swizzle (NSColor.controlAccentColor + invalidation
// notification) lives in App/AccentColorSwizzler.swift.

// Raw values are the canonical time-format indices used across the app.
// 2/5/8 were separator rows in the legacy picker and intentionally have
// no enum case; the gap is kept stable so persisted values still decode.
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

extension TimeFormat {
    /// Formats whose rendered time includes seconds ("ss"). These are the
    /// formats that put StatusItemHandler's menubar timer on a per-second tick.
    var includesSeconds: Bool {
        switch self {
        case .twelveHourWithSeconds, .twentyFourHourWithSeconds,
             .twelveHourWithLeadingZeroAndSeconds, .twelveHourWithoutAmPmAndSeconds:
            return true
        case .twelveHour, .twentyFourHour, .twelveHourWithLeadingZero,
             .twelveHourWithoutAmPm, .epoch:
            return false
        }
    }

    /// True for the 24-hour clock formats.
    var isTwentyFourHour: Bool {
        self == .twentyFourHour || self == .twentyFourHourWithSeconds
    }

    /// The v4-picker format for a 12/24-hour choice, carrying the seconds
    /// preference along. Lets the Menu Bar pane's 24-hour toggle and presets
    /// flip the hour style without discarding a "… with seconds" selection
    /// made in Settings › Appearance.
    static func standard(twentyFourHour: Bool, seconds: Bool) -> TimeFormat {
        switch (twentyFourHour, seconds) {
        case (false, false): return .twelveHour
        case (false, true): return .twelveHourWithSeconds
        case (true, false): return .twentyFourHour
        case (true, true): return .twentyFourHourWithSeconds
        }
    }
}

// Stable string name for typed preference enums via the JSONNameDecodable
// protocol (declared near the top of this file). Used by SettingsManager v2
// JSON export ("compact" instead of 0). Names are derived from the Swift
// case identifier — keep them stable across releases since users' export
// files persist them.
extension Theme: JSONNameDecodable {}
extension RelativeDateDisplay: JSONNameDecodable {}
extension AppPresentation: JSONNameDecodable {}
extension TimeFormat: JSONNameDecodable {}

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

    // String-backed enum (the only one in the typed surface). Default falls
    // through to `.astonMartin` so a clean install matches the shipped
    // Aston Martin tone — matching the previous hardcoded asset catalog.
    var teamAccent: TeamAccent {
        get {
            guard let raw = userDefaults.string(forKey: UserDefaultKeys.teamAccent),
                  let team = TeamAccent(rawValue: raw) else {
                return TeamAccent.default
            }
            return team
        }
        set { userDefaults.set(newValue.rawValue, forKey: UserDefaultKeys.teamAccent) }
    }
}
