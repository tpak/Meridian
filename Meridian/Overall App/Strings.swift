// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa

public enum UserDefaultKeys {
    static let emptyString = ""
    static let defaultPreferenceKey = "defaultPreferences"
    static let timezoneName = "formattedAddress"
    static let customLabel = "customLabel"
    static let selectedTimeZoneFormatKey = "is24HourFormatSelected"
    static let timezoneID = "timezoneID"
    static let placeIdentifier = "place_id"
    static let relativeDateKey = "relativeDate"
    static let themeKey = "defaultTheme"
    static let showDayInMenu = "showDay"
    static let showDateInMenu = "showDate"
    static let showPlaceInMenu = "showPlaceName"
    static let displayFutureSliderKey = "displayFutureSlider"
    static let startAtLogin = "startAtLogin"
    static let showAppInForeground = "displayAppAsForegroundApp"
    static let sunriseSunsetTime = "showSunriseSetTime"
    static let userFontSizePreference = "userFontSize"
    static let truncateTextLength = "truncateTextLength"
    static let futureSliderRange = "sliderDayRange"
    static let appDisplayOptions = "com.tpak.meridian.appDisplayOptions"
    static let testingLaunchArgument = "isUITesting"
    static let debugLoggingEnabled = "com.tpak.meridian.debugLoggingEnabled"
    static let betaUpdatesEnabled = "com.tpak.meridian.betaUpdatesEnabled"
    static let latitude = "latitude"
    static let longitude = "longitude"
    // One-shot install/migration flags — raw string values preserved from the pre-typed-key era; do NOT change.
    static let hasSetAutoUpdateDefault = "HasSetAutoUpdateDefault"
    static let hasFixedAutoUpdateSync = "HasFixedAutoUpdateSync"
    static let hasSetStartAtLoginDefault = "HasSetStartAtLoginDefault"

    // MARK: - Modernized typed-storage keys (issue #97)
    // These replace the legacy inverted-bool / int-encoded keys above.
    // AppDefaults.runBoolSemanticsMigration moves user data from the legacy
    // keys to these on first launch of the modernized build, then deletes
    // the legacy keys.
    //
    // Names intentionally do NOT use the com.tpak.meridian.* prefix used by
    // other namespaced keys (appDisplayOptions, etc.). Two reasons:
    // (1) NSUserDefaultsController storyboard bindings of the
    // form values.<key> traverse dots as nested keypaths and don't work
    // cleanly for dotted keys; (2) @objc dynamic var floatOnTop on
    // UserDefaults can only emit KVO notifications for keypath \.floatOnTop
    // when the underlying UserDefaults key string matches the property
    // identifier, which can't contain dots.
    static let showSunriseSunset = "showSunriseSunset"
    static let showFutureSlider = "showFutureSlider"
    static let showDayInMenubar = "showDayInMenubar"
    static let showDateInMenubar = "showDateInMenubar"
    static let showPlaceNameInMenubar = "showPlaceNameInMenubar"
    static let floatOnTop = "floatOnTop"
    static let timeFormat = "timeFormat"
    // Seconds in the menu-bar clock only (Settings › Menu Bar › Seconds).
    // Independent of `timeFormat`'s seconds, which drives the Daybreak
    // popover — UAT: seconds crowd the menu bar but are fine in the popover.
    // Read via DataStore.menubarShowSeconds / menubarTimezoneFormat().
    static let showSecondsInMenubar = "showSecondsInMenubar"

    // One-time migration flag. Set after runBoolSemanticsMigration completes
    // its first successful pass; read on every launch to make the migration
    // idempotent.
    static let boolSemanticsMigrationV1 = "com.tpak.meridian.boolSemanticsMigrationV1"

    // One-time migration flag for the stuck-home-row fix. Heals stored
    // timezone rows whose `isSystemTimezone` flag drifted from the actual
    // system timezone (e.g. user added a row while traveling, then returned
    // home — the old row stayed flagged and started rendering local time
    // under its original city label). See runHomeRowMigrationV1.
    static let homeRowMigrationV1 = "com.tpak.meridian.homeRowMigrationV1"

    // One-time cleanup flag for artifacts left in the app's UserDefaults by the
    // original Clocker codebase and very early Meridian builds: keys under the
    // previous author's `com.abhishek.` namespace and legacy `Clocker` AppKit
    // autosave entries. Current code never writes these. See
    // runLegacyArtifactCleanupV1.
    static let legacyArtifactCleanupV1 = "com.tpak.meridian.legacyArtifactCleanupV1"

    // One-time flag for seeding the default global shortcut (⌃⌥⌘T) on first launch, so the app ships
    // with a working hot key out of the box. Set after the seed runs (even when it skips because the
    // user already chose a shortcut) so a later *clear* by the user isn't re-seeded on the next
    // launch. See AppDefaults.seedDefaultGlobalShortcutIfNeeded.
    static let defaultGlobalShortcutSeededV1 = "com.tpak.meridian.defaultGlobalShortcutSeededV1"

    // F1 team accent color selection. Stored as TeamAccent.rawValue (String).
    // See DataStore.swift for the enum definition and resolved NSColor.
    static let teamAccent = "com.tpak.meridian.teamAccent"

    // Tahoe (macOS 26+) silently classifies a third-party NSStatusItem as
    // `.ephemeral` until the user enables the app in Control Center → Menu
    // Bar Only. Set to true after the first-launch onboarding NSAlert has
    // been shown so we don't re-prompt on every launch. See issue #125.
    static let tahoeOnboardingShown = "com.tpak.meridian.tahoeOnboardingShown"
}
