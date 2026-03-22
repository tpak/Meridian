// Copyright © 2015 Abhishek Banthia

@testable import Meridian
import XCTest

final class LocalizationTests: XCTestCase {

    // All string keys actively used in the codebase via .localized() or NSLocalizedString()
    private let activeKeys: [String] = [
        // NSLocalizedString keys (PreferencesViewController)
        "No Timezone Selected",
        "Max Timezones Selected",
        "Max Search Characters",
        "Sort by Time Difference",
        "Sort by Name",
        "Sort by Label",
        "Add Button Title",
        "Close Button Title",
        // NSLocalizedString keys (NoTimezoneView)
        "No places added",
        // NSLocalizedString keys (TimezoneAdditionHandler)
        "Search Field Placeholder",
        // .localized() keys (PreferencesViewController)
        "You're offline, maybe?",
        "Try again, maybe?",
        "The Internet connection appears to be offline.",
        // .localized() keys (AppearanceViewController)
        "Favourite a timezone to enable menubar display options.",
        "Time Format",
        "Panel Theme",
        "Day Display Options",
        "Time Scroller",
        "Show Sunrise/Sunset",
        "Larger Text",
        "Future Slider Range",
        "Include Date",
        "Include Day",
        "Include Place Name",
        "Menubar Mode",
        "Preview",
        "Miscellaneous",
        // .localized() keys (TimezoneCellView)
        "Copied to Clipboard",
        // .localized() keys (AboutView)
        "Feedback is always welcome:",
        // .localized() keys (TimezoneDataOperations)
        "Daylights Saving transition will occur in < 24 hours",
    ]

    func testAllActiveKeysResolveToNonEmptyStrings() {
        let bundle = Bundle(for: AppDelegate.self)
        for key in activeKeys {
            let localized = bundle.localizedString(forKey: key, value: "**NOT_FOUND**", table: nil)
            XCTAssertNotEqual(localized, "**NOT_FOUND**",
                              "Localization key '\(key)' not found in Localizable strings")
            XCTAssertFalse(localized.isEmpty,
                           "Localization key '\(key)' resolved to empty string")
        }
    }

    func testLocalizedExtensionWorks() {
        // Verify the .localized() extension returns a non-empty value for a known key
        let result = "No places added".localized()
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, "No places added")
    }

    func testPreferencesConstantsAreLocalized() {
        // These are initialized at static level — verify they resolved
        XCTAssertFalse(PreferencesConstants.noTimezoneSelectedErrorMessage.isEmpty)
        XCTAssertFalse(PreferencesConstants.maxTimezonesErrorMessage.isEmpty)
        XCTAssertFalse(PreferencesConstants.maxCharactersAllowed.isEmpty)
        XCTAssertFalse(PreferencesConstants.noInternetConnectivityError.isEmpty)
        XCTAssertFalse(PreferencesConstants.tryAgainMessage.isEmpty)
        XCTAssertFalse(PreferencesConstants.offlineErrorMessage.isEmpty)
    }
}
