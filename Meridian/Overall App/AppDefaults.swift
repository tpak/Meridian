// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLoggerKit
import CoreModelKit

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

        // Drop leftover keys from the original Clocker codebase / early Meridian
        // builds. Runs before register(defaults:) for consistency with the other
        // migrations; it only touches legacy keys, so order is not critical.
        runLegacyArtifactCleanupV1(on: defaults)

        defaults.register(defaults: defaultsDictionary())

        // Heal any rows whose isSystemTimezone flag drifted from the actual
        // current system timezone. Runs after the row blob is read so the
        // healed blob is what we write back.
        let healed = runHomeRowMigrationV1(on: timezones, defaults: defaults)
        store.setTimezones(healed)
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

        // theme, relativeDate, appDisplayOptions keep their existing key
        // strings — they're already namespaced and not semantically inverted.
        // The typed accessors layer enums over them without renaming.

        defaults.set(true, forKey: UserDefaultKeys.boolSemanticsMigrationV1)
    }

    /// One-time cleanup of artifacts left in the app's UserDefaults by the
    /// original Clocker codebase and very early Meridian builds: keys under the
    /// previous author's `com.abhishek.` namespace (e.g.
    /// `com.abhishek.appDisplayOptions`) and legacy `Clocker` AppKit autosave
    /// entries (e.g. `NSStatusItem Preferred Position ClockerStatusItem`).
    /// Current code never writes these, so fresh installs are unaffected — this
    /// only tidies machines upgrading from those builds.
    ///
    /// Idempotent: guarded by `UserDefaultKeys.legacyArtifactCleanupV1`. Public
    /// for tests.
    class func runLegacyArtifactCleanupV1(on defaults: UserDefaults) {
        guard !defaults.bool(forKey: UserDefaultKeys.legacyArtifactCleanupV1) else {
            return
        }

        for key in defaults.dictionaryRepresentation().keys where isLegacyArtifactKey(key) {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: UserDefaultKeys.legacyArtifactCleanupV1)
    }

    /// True for UserDefaults keys that are leftovers from Clocker / the previous
    /// author's namespace and are no longer written by Meridian. Meridian's own
    /// keys live under `com.tpak.meridian.` and use the `Meridian…` autosave
    /// names, so neither pattern collides with current state.
    static func isLegacyArtifactKey(_ key: String) -> Bool {
        key.hasPrefix("com.abhishek.") || key.contains("Clocker")
    }

    /// One-time migration that heals the "stuck home row" bug. Two failure
    /// modes are corrected:
    ///   1. Rows whose `isSystemTimezone == true` but whose persisted
    ///      `timezoneID` no longer matches the current system timezone
    ///      (e.g. user added "Australia/Melbourne" while traveling, then
    ///      returned to "America/Denver"). These rows still rendered the
    ///      local system time under the original city's label and lit up
    ///      the home indicator — clear the flag.
    ///   2. More than one row carries `isSystemTimezone == true`. Pick the
    ///      one that actually matches the current system timezone (or the
    ///      first one if none does) and clear the flag on the rest.
    ///
    /// Idempotent: guarded by `UserDefaultKeys.homeRowMigrationV1`. Public
    /// for tests. Returns the (possibly rewritten) `[Data]` array; callers
    /// must persist it via `DataStore.setTimezones`.
    @discardableResult
    class func runHomeRowMigrationV1(on timezones: [Data], defaults: UserDefaults) -> [Data] {
        guard !defaults.bool(forKey: UserDefaultKeys.homeRowMigrationV1) else {
            return timezones
        }

        let currentSystemTimezone = TimeZone.autoupdatingCurrent.identifier

        // Decode once. Track each entry by its index so we can rewrite in place.
        let decoded: [(idx: Int, model: TimezoneData?)] = timezones.enumerated().map { (i, blob) in
            (i, TimezoneData.customObject(from: blob))
        }

        let flaggedIndices = decoded.compactMap { entry -> Int? in
            guard let m = entry.model, m.isSystemTimezone else { return nil }
            return entry.idx
        }

        // Decide which single row (if any) should keep the flag. Prefer a
        // flagged row that matches the current system tz; otherwise prefer
        // the first flagged row whose stored timezoneID matches; otherwise
        // an unflagged row whose timezoneID matches the system tz.
        var keepIndex: Int? = flaggedIndices.first { idx in
            decoded[idx].model?.timezoneID == currentSystemTimezone
        }

        if keepIndex == nil {
            keepIndex = decoded.first { entry in
                entry.model?.timezoneID == currentSystemTimezone && entry.model?.isSystemTimezone == false
            }?.idx
        }

        // Walk all rows and rewrite as needed.
        var rewritten = timezones
        for entry in decoded {
            guard let model = entry.model else { continue }
            let shouldBeFlagged = (entry.idx == keepIndex)
            if model.isSystemTimezone != shouldBeFlagged {
                model.isSystemTimezone = shouldBeFlagged
                if let blob = NSKeyedArchiver.secureArchive(with: model) {
                    rewritten[entry.idx] = blob
                }
            }
        }

        defaults.set(true, forKey: UserDefaultKeys.homeRowMigrationV1)
        return rewritten
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
            UserDefaultKeys.truncateTextLength: AppDefaultValues.defaultTruncateTextLength,

            // F1 team accent. Default preserves the Aston Martin look that
            // was hardcoded in the asset catalog before this feature shipped.
            UserDefaultKeys.teamAccent: TeamAccent.default.rawValue,

            // Tahoe (macOS 26+) menubar block onboarding flag. False until
            // the first-launch dialog has been shown. See issue #125.
            UserDefaultKeys.tahoeOnboardingShown: false
        ]
    }
}

extension UserDefaults {
    // Use this with caution. Exposing this for debugging purposes only.
    func wipe(for bundleID: String = "com.tpak.Meridian") {
        removePersistentDomain(forName: bundleID)
    }
}
