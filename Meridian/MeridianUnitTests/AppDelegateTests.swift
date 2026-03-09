// Copyright © 2015 Abhishek Banthia

import CoreModelKit
import XCTest

@testable import Meridian

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
        let cleaned = DataStore.shared().timezones().filter {
            let tz = TimezoneData.customObject(from: $0)
            return tz?.formattedAddress != "MenubarTimezone"
        }
        DataStore.shared().setTimezones(cleaned)
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
        XCTAssertEqual(items.first?.title, "Toggle Panel")
        XCTAssertEqual(items[1].title, "Settings")
        XCTAssertEqual(items[1].keyEquivalent, ",")
        XCTAssertEqual(items[2].title, "Hide from Dock")

        // Test selections
        XCTAssertEqual(items.first?.action, #selector(AppDelegate.togglePanel(_:)))
        XCTAssertEqual(items[2].action, #selector(AppDelegate.hideFromDock))

        items.forEach { menuItem in
            XCTAssertTrue(menuItem.isEnabled)
        }
    }

    func testSetupMenubarTimer() {
        let subject = NSApplication.shared.delegate as? AppDelegate

        let statusItemHandler = subject?.statusItemForPanel()
        XCTAssertEqual(statusItemHandler?.statusItem.autosaveName, NSStatusItem.AutosaveName("ClockerStatusItem"))
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
        XCTAssertEqual(statusItemHandler?.statusItem.button?.subviews, [])
        XCTAssertEqual(statusItemHandler?.statusItem.button?.title, UserDefaultKeys.emptyString)
        XCTAssertNotNil(statusItemHandler?.statusItem.button?.image)
        XCTAssertEqual(statusItemHandler?.statusItem.button?.imagePosition, .imageOnly)
        XCTAssertEqual(statusItemHandler?.statusItem.button?.toolTip, "Meridian")
    }

    func testCompactModeMenubarSetup() throws {
        let subject = NSApplication.shared.delegate as? AppDelegate
        let olderTimezones = DataStore.shared().timezones()
        let olderCompactMode = UserDefaults.standard.integer(forKey: UserDefaultKeys.menubarCompactMode)
        defer {
            DataStore.shared().setTimezones(olderTimezones)
            UserDefaults.standard.set(olderCompactMode, forKey: UserDefaultKeys.menubarCompactMode)
        }

        // Ensure compact mode is active
        UserDefaults.standard.set(0, forKey: UserDefaultKeys.menubarCompactMode)

        let timezone1 = TimezoneData()
        timezone1.timezoneID = TimeZone.autoupdatingCurrent.identifier
        timezone1.formattedAddress = "MenubarTimezone"
        timezone1.isFavourite = 1

        let encodedTimezone = try XCTUnwrap(NSKeyedArchiver.clocker_archive(with: timezone1))
        DataStore.shared().setTimezones([encodedTimezone])

        subject?.setupMenubarTimer()
        let statusItemHandler = subject?.statusItemForPanel()
        XCTAssertNotNil(statusItemHandler?.statusItem.button)
    }

    func testStandardModeMenubarSetup() throws {
        let olderTimezones = DataStore.shared().timezones()
        let olderCompactMode = UserDefaults.standard.integer(forKey: UserDefaultKeys.menubarCompactMode)
        defer {
            UserDefaults.standard.set(olderCompactMode, forKey: UserDefaultKeys.menubarCompactMode)
            DataStore.shared().setTimezones(olderTimezones)
        }

        UserDefaults.standard.set(1, forKey: UserDefaultKeys.menubarCompactMode) // Set the menubar mode to standard

        let subject = NSApplication.shared.delegate as? AppDelegate
        let statusItemHandler = subject?.statusItemForPanel()
        subject?.setupMenubarTimer()

        if olderTimezones.isEmpty {
            XCTAssertNotNil(statusItemHandler?.statusItem.button?.image)
        } else {
            XCTAssertTrue(statusItemHandler?.statusItem.button?.title != nil)
        }

        let timezone1 = TimezoneData()
        timezone1.timezoneID = TimeZone.autoupdatingCurrent.identifier
        timezone1.formattedAddress = "MenubarTimezone"
        timezone1.isFavourite = 1

        let encodedTimezone = try XCTUnwrap(NSKeyedArchiver.clocker_archive(with: timezone1))
        DataStore.shared().setTimezones([encodedTimezone])

        subject?.setupMenubarTimer()

        XCTAssertEqual(subject?.statusItemForPanel().statusItem.button?.subviews.isEmpty, true) // This will be nil for standard mode
    }
}
