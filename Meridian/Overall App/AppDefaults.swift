// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

private enum AppDefaultValues {
    static let defaultUserFontSize: Int = 4
    static let defaultFutureSliderRange: Int = 6
    static let defaultTruncateTextLength: Int = 30
}

class AppDefaults {
    class func initialize(with store: DataStore, defaults: UserDefaults) {
        initializeDefaults(with: store, defaults: defaults)
    }

    private class func initializeDefaults(with store: DataStore, defaults: UserDefaults) {
        let timezones = store.timezones()

        // Migrate legacy inverted-bool / int-encoded keys to typed storage
        // BEFORE registering defaults — migration only acts on user-set values
        // (object(forKey:) returning non-nil from the persistent domain), so
        // running it before register(defaults:) keeps registered fallbacks
        // out of the migration's read path.
        runBoolSemanticsMigration(on: defaults)

        defaults.register(defaults: defaultsDictionary())

        store.setTimezones(timezones)
    }

    /// One-time migration that converts legacy inverted-bool and int-encoded
    /// preference keys to the modernized typed schema (issue #97). Idempotent:
    /// guarded by `UserDefaultKeys.boolSemanticsMigrationV1`. Public for tests.
    class func runBoolSemanticsMigration(on defaults: UserDefaults) {
        guard !defaults.bool(forKey: UserDefaultKeys.boolSemanticsMigrationV1) else {
            return
        }

        // Inverted bools: legacy 0 = show, 1 = hide → typed Bool (true = show).
        migrateInvertedBool(legacy: UserDefaultKeys.sunriseSunsetTime,
                            target: UserDefaultKeys.showSunriseSunset,
                            in: defaults)
        migrateInvertedBool(legacy: UserDefaultKeys.displayFutureSliderKey,
                            target: UserDefaultKeys.showFutureSlider,
                            in: defaults)
        migrateInvertedBool(legacy: UserDefaultKeys.showDayInMenu,
                            target: UserDefaultKeys.showDayInMenubar,
                            in: defaults)
        migrateInvertedBool(legacy: UserDefaultKeys.showDateInMenu,
                            target: UserDefaultKeys.showDateInMenubar,
                            in: defaults)
        migrateInvertedBool(legacy: UserDefaultKeys.showPlaceInMenu,
                            target: UserDefaultKeys.showPlaceNameInMenubar,
                            in: defaults)

        // Non-inverted bool: legacy 1 = floatOnTop, 0 = menubar.
        if let legacyValue = defaults.object(forKey: UserDefaultKeys.showAppInForeground) as? Int {
            defaults.set(legacyValue == 1, forKey: UserDefaultKeys.floatOnTop)
            defaults.removeObject(forKey: UserDefaultKeys.showAppInForeground)
        }

        // Wide enum: time format index moves to a clearer key but keeps its
        // Int storage (raw value matches NSPopUpButton selectedIndex).
        if let legacyValue = defaults.object(forKey: UserDefaultKeys.selectedTimeZoneFormatKey) as? NSNumber {
            defaults.set(legacyValue.intValue, forKey: UserDefaultKeys.timeFormat)
            defaults.removeObject(forKey: UserDefaultKeys.selectedTimeZoneFormatKey)
        }

        // theme, relativeDate, appDisplayOptions, menubarCompactMode keep
        // their existing key strings — they're already namespaced and not
        // semantically inverted. The typed accessors layer enums over them
        // without renaming.

        defaults.set(true, forKey: UserDefaultKeys.boolSemanticsMigrationV1)
    }

    private class func migrateInvertedBool(legacy: String, target: String, in defaults: UserDefaults) {
        // Read the persistent value only — register(defaults:) hasn't been
        // called yet, so object(forKey:) returns nil iff the user never set
        // this key explicitly. In that case we leave both keys untouched and
        // let the new key's registered default take over below.
        guard let object = defaults.object(forKey: legacy) else { return }
        let legacyInt = (object as? NSNumber)?.intValue ?? (object as? Int) ?? 1
        defaults.set(legacyInt == 0, forKey: target)
        defaults.removeObject(forKey: legacy)
    }

    private class func defaultsDictionary() -> [String: Any] {
        return [
            // Already-correct enum keys — names unchanged.
            UserDefaultKeys.themeKey: Theme.light.rawValue,
            UserDefaultKeys.relativeDateKey: RelativeDateDisplay.relative.rawValue,
            UserDefaultKeys.appDisplayOptions: AppPresentation.menubarOnly.rawValue,
            UserDefaultKeys.menubarCompactMode: MenubarMode.standard.rawValue,

            // Modernized typed keys (issue #97).
            UserDefaultKeys.showSunriseSunset: false,
            UserDefaultKeys.showFutureSlider: true,
            UserDefaultKeys.showDayInMenubar: true,
            UserDefaultKeys.showDateInMenubar: false,
            UserDefaultKeys.showPlaceNameInMenubar: true,
            UserDefaultKeys.floatOnTop: false,
            UserDefaultKeys.timeFormat: TimeFormat.twelveHour.rawValue,

            // Untouched.
            UserDefaultKeys.startAtLogin: 0,
            UserDefaultKeys.userFontSizePreference: AppDefaultValues.defaultUserFontSize,
            UserDefaultKeys.futureSliderRange: AppDefaultValues.defaultFutureSliderRange,
            UserDefaultKeys.truncateTextLength: AppDefaultValues.defaultTruncateTextLength
        ]
    }
}

extension UserDefaults {
    // Use this with caution. Exposing this for debugging purposes only.
    func wipe(for bundleID: String = "com.tpak.Meridian") {
        removePersistentDomain(forName: bundleID)
    }
}
