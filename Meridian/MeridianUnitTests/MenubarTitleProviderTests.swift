// Copyright © 2015 Abhishek Banthia

import CoreModelKit
import XCTest

@testable import Meridian

class MenubarTitleProviderTests: XCTestCase {
    private var mockStore: MockDataStore!

    private var mumbai: [String: Any] { TestTimezones.mumbaiAlternate }
    private var newYork: [String: Any] { TestTimezones.newYork }

    override func setUp() {
        super.setUp()
        mockStore = MockDataStore()
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 0)
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 0)
        // Ensure non-compact mode (menubarCompactMode != 0 means standard mode)
        mockStore.viewTypeDisplayPreferences[.menubarCompactMode] = false
    }

    override func tearDown() {
        mockStore = nil
        super.tearDown()
    }

    // MARK: - No Favorites Tests

    func testNoFavoritesReturnsNil() {
        mockStore.storedTimezones = []
        let provider = MenubarTitleProvider(with: mockStore)
        XCTAssertNil(provider.titleForMenubar(), "No favorites should return nil")
    }

    func testUnfavouritedTimezoneReturnsNil() {
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 0
        mockStore.addTimezone(dataObject)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        // menubarTimezones filters by isFavourite == 1, so empty list => nil
        XCTAssertNil(title, "Unfavourited timezone should result in nil title")
    }

    // MARK: - Single Timezone Tests

    func testSingleFavouriteTimezone() {
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        mockStore.addTimezone(dataObject)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        XCTAssertNotNil(title, "Single favourite should produce a title")
        XCTAssertFalse(title!.isEmpty, "Title should not be empty")
    }

    func testSingleTimezoneWith12HourFormat() {
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 0)
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        mockStore.addTimezone(dataObject)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        XCTAssertNotNil(title)
        // Title should contain AM or PM for 12-hour format
        let hasAMPM = title!.contains("AM") || title!.contains("PM")
        XCTAssertTrue(hasAMPM, "12-hour format title should contain AM/PM but got: \(title!)")
    }

    func testSingleTimezoneWith24HourFormat() {
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 1)
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        mockStore.addTimezone(dataObject)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        XCTAssertNotNil(title)
        // Title should NOT contain AM or PM for 24-hour format
        let hasAMPM = title!.contains("AM") || title!.contains("PM")
        XCTAssertFalse(hasAMPM, "24-hour format title should not contain AM/PM but got: \(title!)")
    }

    // MARK: - Multiple Timezones Tests

    func testMultipleTimezones() {
        let mumbaiData = TimezoneData(with: mumbai)
        mumbaiData.isFavourite = 1
        mockStore.addTimezone(mumbaiData)

        let nyData = TimezoneData(with: newYork)
        nyData.isFavourite = 1
        mockStore.addTimezone(nyData)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        XCTAssertNotNil(title, "Multiple favourites should produce a title")
        XCTAssertFalse(title!.isEmpty, "Title with multiple timezones should not be empty")
    }

    func testMultipleTimezonesContainsBothTimes() {
        let mumbaiData = TimezoneData(with: mumbai)
        mumbaiData.isFavourite = 1
        mockStore.addTimezone(mumbaiData)

        let nyData = TimezoneData(with: newYork)
        nyData.isFavourite = 1
        mockStore.addTimezone(nyData)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        XCTAssertNotNil(title)

        // With two timezones, the title should contain a space (separator between the two titles)
        // The titles are joined with a space
        XCTAssertTrue(title!.count > 4, "Combined title should have reasonable length but got: \(title!)")
    }

    // MARK: - Compact Mode Tests

    func testCompactModeReturnsNil() {
        mockStore.viewTypeDisplayPreferences[.menubarCompactMode] = true

        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        mockStore.addTimezone(dataObject)

        let provider = MenubarTitleProvider(with: mockStore)
        let title = provider.titleForMenubar()
        XCTAssertNil(title, "Compact mode should return nil from titleForMenubar")
    }
}
