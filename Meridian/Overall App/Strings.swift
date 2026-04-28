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
    static let showSunriseSunset = "com.tpak.meridian.showSunriseSunset"
    static let showFutureSlider = "com.tpak.meridian.showFutureSlider"
    static let showDayInMenubar = "com.tpak.meridian.showDayInMenubar"
    static let showDateInMenubar = "com.tpak.meridian.showDateInMenubar"
    static let showPlaceNameInMenubar = "com.tpak.meridian.showPlaceNameInMenubar"
    static let floatOnTop = "com.tpak.meridian.floatOnTop"
    static let timeFormat = "com.tpak.meridian.timeFormat"

    // One-time migration flag. Set after runBoolSemanticsMigration completes
    // its first successful pass; read on every launch to make the migration
    // idempotent.
    static let boolSemanticsMigrationV1 = "com.tpak.meridian.boolSemanticsMigrationV1"
}
