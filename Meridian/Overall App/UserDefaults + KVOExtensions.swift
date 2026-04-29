// Copyright © 2015 Abhishek Banthia

import Cocoa

extension UserDefaults {
    @objc dynamic var userFontSize: Int {
        return integer(forKey: UserDefaultKeys.userFontSizePreference)
    }

    @objc dynamic var sliderDayRange: Int {
        return integer(forKey: UserDefaultKeys.futureSliderRange)
    }

    // For KVO notifications to fire, the property name must match the
    // UserDefaults key string. Combine subscribers in PanelController and
    // ParentPanelController watch these to react to user toggles.
    @objc dynamic var floatOnTop: Bool {
        return bool(forKey: UserDefaultKeys.floatOnTop)
    }

    @objc dynamic var showFutureSlider: Bool {
        return bool(forKey: UserDefaultKeys.showFutureSlider)
    }
}
