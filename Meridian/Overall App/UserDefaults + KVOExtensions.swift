// Copyright © 2015 Abhishek Banthia

import Cocoa

extension UserDefaults {
    @objc dynamic var displayFutureSlider: Int {
        return integer(forKey: UserDefaultKeys.displayFutureSliderKey)
    }

    @objc dynamic var userFontSize: Int {
        return integer(forKey: UserDefaultKeys.userFontSizePreference)
    }

    @objc dynamic var sliderDayRange: Int {
        return integer(forKey: UserDefaultKeys.futureSliderRange)
    }

    // Property name must match the UserDefaults key string for KVO notifications to fire.
    @objc dynamic var displayAppAsForegroundApp: Int {
        return integer(forKey: UserDefaultKeys.showAppInForeground)
    }
}
