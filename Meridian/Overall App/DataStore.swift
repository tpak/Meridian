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

    /// Resolved accent color used by PanelController and CustomSliderCell.
    /// Alpha 0.85 matches the toned-down Aston Martin shipping value (PR
    /// e4ad82b2) so saturation feels consistent across teams.
    var accentColor: NSColor {
        let h = hex
        let red = CGFloat(Int(h.prefix(2), radix: 16) ?? 0) / 255.0
        let green = CGFloat(Int(h.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
        let blue = CGFloat(Int(h.suffix(2), radix: 16) ?? 0) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 0.85)
    }

    var jsonName: String { rawValue }

    init?(jsonName: String) {
        guard let match = Self.allCases.first(where: { $0.rawValue == jsonName }) else { return nil }
        self = match
    }
}

extension Notification.Name {
    /// Posted when the user changes the team accent in Appearance settings.
    /// PanelController observes this and triggers a redraw of the slider
    /// fill + pin button tint.
    static let accentColorDidChange = Notification.Name("com.tpak.meridian.accentColorDidChange")
}

// MARK: - controlAccentColor swizzle + invalidation
//
// Why we swizzle:
// Without this, NSColor.controlAccentColor falls through to the
// `Accent Color` colorset in Media.xcassets — a baked-in Aston Martin
// green. So every NSPopUpButton selected indicator, NSSegmentedControl
// segment fill, NSCheckbox check, NSToolbarItem tab icon, and focus
// ring would stay green regardless of which team the user picks.
// We swap the class-method getter at app launch so AppKit's internal
// callers (and our own) get the live team color.
//
// Why a simple swizzle is not enough:
// controlAccentColor is implemented as an NSDynamicSystemColor — a
// dynamic system color whose resolution AppKit caches per
// NSAppearance. Even after the swizzle returns a new color value,
// AppKit reuses the previously-cached resolution for any surface that
// has already been drawn. NSToolbarItem also caches its tinted
// bitmap separately. Result: switching team A → team B in place does
// nothing visible until some other event (tab nav, window
// resize) forces a re-render.
//
// `NSApplication.mer_invalidateAccentEverywhere` performs the three
// kinds of invalidation that, together, cover every visible surface:
//   1. Re-set NSToolbarItem.image and NSTabViewItem.label/.image so
//      the toolbar's tinted-bitmap cache is dropped.
//   2. Recursive setNeedsDisplay on every view (and its CALayer) so
//      layer-backed bitmaps repaint with the new accent.
//   3. Toggle window.appearance through its current effective value
//      so AppKit drops the NSDynamicSystemColor cache for that
//      window's view tree without causing a light/dark flash.
extension NSColor {
    @objc class func mer_currentTeamAccentColor() -> NSColor {
        DataStore.shared().teamAccent.accentColor
    }

    /// Intercepts `NSColor(named:)` lookups. When the name is the asset
    /// catalog's accent entry ("AccentColor" / "Accent Color"), return
    /// the live team accent. All other names fall through to the
    /// original implementation.
    ///
    /// This is needed because AppKit's selected-toolbar-tab background
    /// reads the asset catalog directly via `+colorNamed:` instead of
    /// going through `+controlAccentColor`. Swizzling only the latter
    /// left the tab background showing whatever was baked into
    /// `Accent Color.colorset` (Aston Martin green) regardless of the
    /// user's team selection.
    @objc class func mer_swizzledColorNamed(_ name: String) -> NSColor? {
        if name == "AccentColor" || name == "Accent Color" {
            return DataStore.shared().teamAccent.accentColor
        }
        // After method_exchangeImplementations, this call lands on the
        // original `+colorNamed:` because the implementations were
        // swapped at runtime.
        return mer_swizzledColorNamed(name)
    }

    /// Idempotent — guarded with a static flag so repeated calls are no-ops.
    static func installTeamAccentSwizzle() {
        struct Once { static var done = false }
        guard !Once.done else { return }
        Once.done = true

        // Swizzle +controlAccentColor only. This covers NSPopUpButton,
        // NSSegmentedControl, NSCheckbox, NSSlider, focus rings, etc.
        // The selected-tab pill background is left to read the asset
        // catalog (a neutral light gray) — chasing it through colorNamed:
        // and private _selectionMaterialTintColor swizzles wasn't reliably
        // working and the gray is unobtrusive enough that it doesn't fight
        // the team color elsewhere.
        let originalSel = #selector(getter: NSColor.controlAccentColor)
        let customSel = #selector(NSColor.mer_currentTeamAccentColor)
        guard let original = class_getClassMethod(NSColor.self, originalSel),
              let custom = class_getClassMethod(NSColor.self, customSel) else {
            return
        }
        method_exchangeImplementations(original, custom)
    }
}

extension NSApplication {
    /// Lets observers (PanelController, OneWindowController) repaint
    /// the surfaces we explicitly tint with the team color: panel pin
    /// button, slider chevrons + reset button, Preferences toolbar
    /// icons (palette-baked SF Symbols).
    ///
    /// We do NOT attempt to invalidate AppKit's NSDynamicSystemColor
    /// caches here. Every approach we tried (window.appearance
    /// toggle, NSApp.deactivate/activate, tabStyle toggle, recursive
    /// setNeedsDisplay) had at least one failure mode. macOS doesn't
    /// expose a runtime API for changing controlAccentColor and
    /// expecting AppKit's cached renderings to follow. The reliable
    /// path is the one Apple takes for the system-wide accent change:
    /// quit and relaunch. AppearanceViewController offers that as a
    /// modal choice when the user picks a team.
    func mer_invalidateAccentEverywhere() {
        NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
    }
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
