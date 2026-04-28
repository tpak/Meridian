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
    static let longStatusBarWarningMessage = "com.tpak.meridian.longStatusBarWarning"
    static let testingLaunchArgument = "isUITesting"
    static let menubarCompactMode = "com.tpak.meridian.menubarCompactMode"
    static let defaultMenubarMode = "com.tpak.meridian.shouldDefaultToCompactMode"
    static let installHomeIndicatorObject = "installHomeIndicatorObject"
    static let switchToCompactModeAlert = "com.tpak.meridian.switchToCompactMode"
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
    // other namespaced keys (appDisplayOptions, menubarCompactMode, etc.).
    // Two reasons: (1) NSUserDefaultsController storyboard bindings of the
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
}
