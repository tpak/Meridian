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

        // Register the usual suspects
        defaults.register(defaults: defaultsDictionary())

        store.setTimezones(timezones)
    }

    private class func defaultsDictionary() -> [String: Any] {
        return [UserDefaultKeys.themeKey: 0,
                UserDefaultKeys.displayFutureSliderKey: 0,
                UserDefaultKeys.selectedTimeZoneFormatKey: 0, // 12-hour format
                UserDefaultKeys.relativeDateKey: 0,
                UserDefaultKeys.showDayInMenu: 0,
                UserDefaultKeys.showDateInMenu: 1,
                UserDefaultKeys.showPlaceInMenu: 0,
                UserDefaultKeys.startAtLogin: 0,
                UserDefaultKeys.sunriseSunsetTime: 1,
                UserDefaultKeys.userFontSizePreference: AppDefaultValues.defaultUserFontSize,
                UserDefaultKeys.showAppInForeground: 0,
                UserDefaultKeys.futureSliderRange: AppDefaultValues.defaultFutureSliderRange,
                UserDefaultKeys.truncateTextLength: AppDefaultValues.defaultTruncateTextLength,
                UserDefaultKeys.appDisplayOptions: 0,
                UserDefaultKeys.menubarCompactMode: 1]
    }
}

extension UserDefaults {
    // Use this with caution. Exposing this for debugging purposes only.
    func wipe(for bundleID: String = "com.tpak.Meridian") {
        removePersistentDomain(forName: bundleID)
    }
}
