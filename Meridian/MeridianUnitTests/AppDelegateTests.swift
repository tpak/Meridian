// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import CoreModelKit
import XCTest

@testable import Meridian

/// Integration tests for AppDelegate that require the live NSApplication.shared singleton.
/// These tests verify observable behavior of the running app (menubar display modes,
/// status item state transitions) and cannot be fully isolated from the app lifecycle.
/// DataStore cleanup is performed in tearDown to prevent test pollution.
class AppDelegateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // When defaults are empty (e.g. cleared by a parallel test worker),
        // the test host enters onboarding and never calls continueUsually(),
        // leaving statusBarHandler nil. Ensure the app is fully initialized.
        let subject = NSApplication.shared.delegate as? AppDelegate
        subject?.continueUsually()
    }

    override func tearDown() {
        // Remove test-specific timezone entries that could pollute UserDefaults
        // when tests run in parallel across multiple workers.
        cleanupSingletonTimezones { tz in
            return tz?.formattedAddress == "MenubarTimezone"
        }
        super.tearDown()
    }

    func testStatusItemIsInitialized() throws {
        let subject = NSApplication.shared.delegate as? AppDelegate
        let statusHandler = subject?.statusItemForPanel()
        XCTAssertNotNil(statusHandler)
    }

    func testDockMenu() throws {
        let subject = NSApplication.shared.delegate as? AppDelegate
        let dockMenu = subject?.applicationDockMenu(NSApplication.shared)
        let items = dockMenu?.items ?? []

        XCTAssertEqual(dockMenu?.title, "Quick Access")
        XCTAssertEqual(items[0].title, "Toggle Panel")
        XCTAssertEqual(items[1].title, "Settings")
        XCTAssertEqual(items[1].keyEquivalent, ",")
        XCTAssertEqual(items[2].title, "Check for Updates…")
        XCTAssertEqual(items[3].title, "Hide from Dock")

        // Test selections
        XCTAssertEqual(items[0].action, #selector(AppDelegate.togglePanel(_:)))
        XCTAssertEqual(items[3].action, #selector(AppDelegate.hideFromDock))

        items.forEach { menuItem in
            XCTAssertTrue(menuItem.isEnabled)
        }
    }

    func testSetupMenubarTimer() {
        let subject = NSApplication.shared.delegate as? AppDelegate

        let statusItemHandler = subject?.statusItemForPanel()
        XCTAssertEqual(statusItemHandler?.statusItem.autosaveName, NSStatusItem.AutosaveName("MeridianStatusItem"))
    }

    func testActivationPolicy() {
        let subject = NSApplication.shared.delegate as? AppDelegate
        let previousOption = UserDefaults.standard.integer(forKey: UserDefaultKeys.appDisplayOptions)
        if previousOption == 0 {
            XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        } else {
            XCTAssertEqual(NSApp.activationPolicy(), .regular)
        }

        subject?.hideFromDock()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func testMenubarInvalidationToIcon() {
        let subject = NSApplication.shared.delegate as? AppDelegate
        subject?.invalidateMenubarTimer(true)
        let statusItemHandler = subject?.statusItemForPanel()

        // Verify that invalidateMenubarTimer transitions the menubar to icon-only mode.
        // We assert the button's observable state: an icon is set, text is cleared, and it's
        // positioned as imageOnly. The implementation detail assertions (subviews, toolTip) are
        // kept because they are side effects of the state transition and help verify the
        // internal state machine completed correctly.

        // Icon should be displayed and text cleared
        XCTAssertNotNil(statusItemHandler?.statusItem.button?.image, "Icon should be displayed in icon mode")
        XCTAssertEqual(statusItemHandler?.statusItem.button?.title, UserDefaultKeys.emptyString, "Title should be empty in icon mode")
        XCTAssertEqual(statusItemHandler?.statusItem.button?.imagePosition, .imageOnly, "Image should be positioned as imageOnly")
        XCTAssertEqual(statusItemHandler?.statusItem.button?.subviews, [], "Subviews should be cleared for icon mode")
        XCTAssertEqual(statusItemHandler?.statusItem.button?.toolTip, "Meridian", "Tooltip should be set to app name")
    }

    func testCompactModeMenubarSetup() throws {
        let subject = NSApplication.shared.delegate as? AppDelegate
        // Integration test: requires DataStore.shared() to drive the live status item handler.
        let olderTimezones = DataStore.shared().timezones()
        defer {
            DataStore.shared().setTimezones(olderTimezones)
        }

        let timezone1 = TimezoneData()
        timezone1.timezoneID = TimeZone.autoupdatingCurrent.identifier
        timezone1.formattedAddress = "MenubarTimezone"
        timezone1.isFavourite = 1

        let encodedTimezone = try XCTUnwrap(NSKeyedArchiver.secureArchive(with: timezone1))
        DataStore.shared().setTimezones([encodedTimezone])

        subject?.setupMenubarTimer()
        let statusItemHandler = subject?.statusItemForPanel()
        XCTAssertNotNil(statusItemHandler?.statusItem.button)
    }

    // Sparkle beta channel (issue #98). Verifies the SPUUpdaterDelegate routes
    // users to the right release channel based on UserDefaultKeys.betaUpdatesEnabled.
    func testAllowedChannels_optedOutByDefault() throws {
        let subject = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let priorValue = UserDefaults.standard.bool(forKey: UserDefaultKeys.betaUpdatesEnabled)
        defer { UserDefaults.standard.set(priorValue, forKey: UserDefaultKeys.betaUpdatesEnabled) }

        UserDefaults.standard.set(false, forKey: UserDefaultKeys.betaUpdatesEnabled)
        XCTAssertEqual(subject.allowedChannels(for: subject.updaterController.updater), [],
                       "Stable users must not see beta-tagged appcast items")
    }

    func testAllowedChannels_optedInExposesBetaChannel() throws {
        let subject = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let priorValue = UserDefaults.standard.bool(forKey: UserDefaultKeys.betaUpdatesEnabled)
        defer { UserDefaults.standard.set(priorValue, forKey: UserDefaultKeys.betaUpdatesEnabled) }

        UserDefaults.standard.set(true, forKey: UserDefaultKeys.betaUpdatesEnabled)
        XCTAssertEqual(subject.allowedChannels(for: subject.updaterController.updater), ["beta"],
                       "Beta opt-in must allow the \"beta\" channel")
    }

    // Coordinate backfill merge. Geocoding a city takes seconds per await, so
    // the user can add/remove cities while the backfill task is suspended. The
    // merge must apply geocoded coordinates onto a FRESH read of the store —
    // matched by stable identity, not array position — so those edits survive.
    func testMergeBackfilledCoordinatesKeepsUserEdits() throws {
        // Launch state: two plain-timezone rows awaiting coordinates.
        let tokyo = TimezoneData()
        tokyo.timezoneID = "Asia/Tokyo"
        tokyo.formattedAddress = "Tokyo"

        let paris = TimezoneData()
        paris.timezoneID = "Europe/Paris"
        paris.formattedAddress = "Paris"

        // While the geocoder ran, the user removed Paris and added Auckland
        // (a geocoded search result that already carries real coordinates).
        let auckland = TimezoneData()
        auckland.timezoneID = "Pacific/Auckland"
        auckland.formattedAddress = "Auckland"
        auckland.latitude = -36.8485
        auckland.longitude = 174.7633

        let tokyoBlob = try XCTUnwrap(NSKeyedArchiver.secureArchive(with: tokyo))
        let aucklandBlob = try XCTUnwrap(NSKeyedArchiver.secureArchive(with: auckland))

        // Both launch-time rows finished geocoding, including the removed one.
        let geocoded: [String: (latitude: Double, longitude: Double)] = [
            AppDelegate.backfillIdentity(for: tokyo): (35.6762, 139.6503),
            AppDelegate.backfillIdentity(for: paris): (48.8566, 2.3522)
        ]

        let merged = AppDelegate.mergeBackfilledCoordinates(current: [tokyoBlob, aucklandBlob],
                                                            geocoded: geocoded)

        XCTAssertEqual(merged.count, 2, "merge must preserve the current list, not the launch snapshot")

        let mergedTokyo = try XCTUnwrap(TimezoneData.customObject(from: merged[0]))
        XCTAssertEqual(mergedTokyo.timezoneID, "Asia/Tokyo")
        XCTAssertEqual(mergedTokyo.latitude, 35.6762, "surviving row gains its geocoded coordinates")
        XCTAssertEqual(mergedTokyo.longitude, 139.6503)

        let mergedAuckland = try XCTUnwrap(TimezoneData.customObject(from: merged[1]))
        XCTAssertEqual(mergedAuckland.timezoneID, "Pacific/Auckland", "city added during backfill must survive")
        XCTAssertEqual(mergedAuckland.latitude, -36.8485, "existing coordinates are left untouched")

        XCTAssertFalse(merged.contains { TimezoneData.customObject(from: $0)?.timezoneID == "Europe/Paris" },
                       "city removed during backfill must not be resurrected")
    }

    // MARK: - Fixed-offset zones (#210)

    func testFixedOffsetZonesAreRecognised() {
        for identifier in ["UTC", "GMT", "GMT+10", "GMT-5", "gmt+3",
                           "Etc/GMT", "Etc/GMT+10", "Etc/UTC", "Zulu", "Universal", "Greenwich"] {
            XCTAssertTrue(AppDelegate.isFixedOffsetZone(identifier),
                          "\(identifier) denotes an offset, not a place, and must never be geocoded")
        }
    }

    func testRealPlaceZonesAreNotTreatedAsFixedOffset() {
        // Guards against an over-broad rule quietly disabling sunrise/sunset for real cities.
        for identifier in ["America/Chicago", "Australia/Melbourne", "Europe/London", "Asia/Kolkata",
                           "America/Argentina/Buenos_Aires", "Pacific/Chatham", "Africa/Bamako"] {
            XCTAssertFalse(AppDelegate.isFixedOffsetZone(identifier),
                           "\(identifier) is a real place and still needs its coordinates")
        }
    }

    func testStripClearsCoordinatesOnFixedOffsetRows() throws {
        // The exact bogus point observed on a live machine: farmland near Seymour, Victoria.
        let utc = TimezoneData()
        utc.timezoneID = "UTC"
        utc.latitude = -37.1960608
        utc.longitude = 145.7897259
        let blob = try XCTUnwrap(NSKeyedArchiver.secureArchive(with: utc))

        let stripped = try XCTUnwrap(AppDelegate.stripFixedOffsetCoordinates(from: [blob]),
                                     "a row with bogus coordinates must be reported as changed")
        let updated = try XCTUnwrap(TimezoneData.customObject(from: stripped[0]))
        XCTAssertNil(updated.latitude)
        XCTAssertNil(updated.longitude)
        XCTAssertEqual(updated.timezoneID, "UTC", "only the coordinates change")
    }

    func testStripLeavesRealCitiesAlone() throws {
        let melbourne = TimezoneData()
        melbourne.timezoneID = "Australia/Melbourne"
        melbourne.latitude = -37.8136
        melbourne.longitude = 144.9631
        let blob = try XCTUnwrap(NSKeyedArchiver.secureArchive(with: melbourne))

        XCTAssertNil(AppDelegate.stripFixedOffsetCoordinates(from: [blob]),
                     "nothing to change means no write — a real city keeps its coordinates")
    }

    func testStripIsIdempotentOnAlreadyCleanRows() throws {
        let utc = TimezoneData()
        utc.timezoneID = "UTC"
        let blob = try XCTUnwrap(NSKeyedArchiver.secureArchive(with: utc))

        XCTAssertNil(AppDelegate.stripFixedOffsetCoordinates(from: [blob]),
                     "a UTC row that already has nil coordinates must not trigger a rewrite every launch")
    }
}
