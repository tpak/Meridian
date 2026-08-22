// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

@testable import Meridian
import XCTest

final class LocalizationTests: XCTestCase {

    // String keys actively used by shipping code, grouped by the file that uses them. Every entry
    // must appear as a literal in a non-test source — `scripts/validate_feature.sh` enforces that,
    // so this list can't drift back into naming surfaces that no longer exist.
    private let activeKeys: [String] = [
        // .localized() keys (AppDelegate — Control Center onboarding alert)
        "One quick setup step",
        "Open Control Center Settings",
        "I've already done this",
        // .localized() keys (StatusItemHandler — status-item fallback menu)
        "Meridian isn't visible in your menu bar",
        "Quit Meridian",
        // String(localized:) keys (Daybreak popover)
        "Your Time",
        "Current Location",
        "Sunrise",
        "Sunset",
        "Now",
        "Home",
        "Double-click to set this time",
        "Add places in Settings to see them here.",
        "Copy all city times",
        "Settings",
        "↺ Back to now",
        // String(localized:) keys (SettingsRootView — sidebar)
        "Cities",
        "Menu Bar",
        "Appearance",
        "Time Travel",
        "General",
        // String(localized:) keys (CitiesPane / CityListModel)
        "Add a city or timezone…",
        "Currently in",
        "Pin to top",
        "Show in menu bar",
        "Set color",
        "Label",
        "Remove",
        "Sort",
        "Time diff",
        // String(localized:) keys (AppearancePane)
        "Theme",
        "Time format",
        "Show seconds",
        "Day display",
        "Sunrise / sunset",
        "Text size",
        "Accent color",
        // String(localized:) keys (MenuBarPane)
        "Preset",
        "Fine-tune",
        "Color dots",
        "Show Meridian in",
        // String(localized:) keys (TimeTravelPane)
        "Travel forward",
        "Travel back",
        "Arrow / snap step",
        "Show Time Scroller",
        // String(localized:) keys (GeneralPane)
        "Start at login",
        "Check for updates",
        "Receive beta releases",
        "Debug logging",
        "Export Settings…",
        "Import Settings…",
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
        let result = "One quick setup step".localized()
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, "One quick setup step")
    }
}
