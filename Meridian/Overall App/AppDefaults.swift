// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

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
                UserDefaultKeys.userFontSizePreference: 4,
                UserDefaultKeys.showAppInForeground: 0,
                UserDefaultKeys.futureSliderRange: 0,
                UserDefaultKeys.truncateTextLength: 30,
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
