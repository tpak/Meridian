// Copyright © 2015 Abhishek Banthia

import Cocoa

public enum UserDefaultKeys {
    static let emptyString = ""
    static let defaultPreferenceKey = "defaultPreferences"
    static let timezoneName = "formattedAddress"
    static let customLabel = "customLabel"
    static let selectedTimeZoneFormatKey = "is24HourFormatSelected"
    static let dragSessionKey = "public.text"
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
    static let appleInterfaceStyleKey = "AppleInterfaceStyle"
    static let debugLoggingEnabled = "com.tpak.meridian.debugLoggingEnabled"
    static let betaUpdatesEnabled = "com.tpak.meridian.betaUpdatesEnabled"
    static let latitude = "latitude"
    static let longitude = "longitude"
    static let nextUpdate = "nextUpdate"

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

    // One-time migration flag. Set after runBoolSemanticsMigration completes
    // its first successful pass; read on every launch to make the migration
    // idempotent.
    static let boolSemanticsMigrationV1 = "com.tpak.meridian.boolSemanticsMigrationV1"

    // F1 team accent color selection. Stored as TeamAccent.rawValue (String).
    // See DataStore.swift for the enum definition and resolved NSColor.
    static let teamAccent = "com.tpak.meridian.teamAccent"

    // Set to true by AppearanceViewController when the user picks a new
    // team and chooses Restart Now in the relaunch prompt. AppDelegate
    // checks this on the next applicationDidFinishLaunching, opens
    // Settings to the Appearance tab, and clears the flag.
    static let reopenAppearanceOnLaunch = "com.tpak.meridian.reopenAppearanceOnLaunch"

    // Tahoe (macOS 26+) silently classifies a third-party NSStatusItem as
    // `.ephemeral` until the user enables the app in Control Center → Menu
    // Bar Only. Set to true after the first-launch onboarding NSAlert has
    // been shown so we don't re-prompt on every launch. See issue #125.
    static let tahoeOnboardingShown = "com.tpak.meridian.tahoeOnboardingShown"
}

// Centralized timing literals. Putting them here makes the rationale for each
// delay easy to find (and to revisit) instead of hiding them as bare numbers
// at call sites.
enum TimingConstants {
    /// Delay before terminating the current process during the team-accent
    /// restart flow. Long enough for `open -n` to register the new launch
    /// before the old process exits — otherwise macOS treats it as a
    /// duplicate-launch suppression and the new instance never appears.
    static let pauseBeforeRelaunchTermination: TimeInterval = 0.2

    /// Delay before opening Settings → Appearance after the team-accent
    /// relaunch completes. Lets AppDelegate finish constructing the panel
    /// and status item before we open Settings on top of them.
    static let openAppearanceAfterRelaunch: TimeInterval = 0.3
}

// Centralized layout literals shared across menubar text-rendering call sites.
// Per-file layout values that aren't shared stay where they're used.
enum LayoutConstants {
    /// Line-height multiple applied to monospaced status-bar text in English
    /// locales. Slightly compresses leading so descenders (p, q, y, g) read
    /// well in the menubar. Non-English locales use 1.0 (no compression).
    static let englishMenubarLineHeightMultiple: CGFloat = 0.92
}
