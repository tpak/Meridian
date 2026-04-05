// Copyright © 2015 Abhishek Banthia

import CoreModelKit
import XCTest

@testable import Meridian

class TimezoneDataOperationsTests: XCTestCase {
    private var mockStore: MockDataStore!

    private var newYork: [String: Any] { TestTimezones.newYork }
    private var tokyo: [String: Any] { TestTimezones.tokyo }
    private var london: [String: Any] { TestTimezones.london }
    private var noCoords: [String: Any] { TestTimezones.noCoords }

    override func setUp() {
        super.setUp()
        mockStore = MockDataStore()
        // Default to 12-hour format
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 0)
        // Default to relative day display
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 0)
    }

    override func tearDown() {
        mockStore = nil
        super.tearDown()
    }

    // MARK: - Time Formatting Tests

    func testTimeFormatting12Hour() {
        let dataObject = TimezoneData(with: newYork)
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 0)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let timeString = operations.time(with: 0)
        XCTAssertFalse(timeString.isEmpty, "Time string should not be empty")
        // 12-hour format should contain AM or PM
        let hasAMPM = timeString.contains("AM") || timeString.contains("PM")
        XCTAssertTrue(hasAMPM, "12-hour format should contain AM/PM but got: \(timeString)")
    }

    func testTimeFormatting24Hour() {
        let dataObject = TimezoneData(with: newYork)
        dataObject.setShouldOverrideGlobalTimeFormat(2) // 24-hour
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let timeString = operations.time(with: 0)
        XCTAssertFalse(timeString.isEmpty, "Time string should not be empty")
        // 24-hour format should NOT contain AM or PM
        let hasAMPM = timeString.contains("AM") || timeString.contains("PM")
        XCTAssertFalse(hasAMPM, "24-hour format should not contain AM/PM but got: \(timeString)")
    }

    func testTimeFormattingWithSeconds() {
        let dataObject = TimezoneData(with: tokyo)
        dataObject.setShouldOverrideGlobalTimeFormat(4) // 12-hour with seconds
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let timeString = operations.time(with: 0)
        // Should have format like "h:mm:ss AM" — two colons
        let colonCount = timeString.filter { $0 == ":" }.count
        XCTAssertEqual(colonCount, 2, "12-hour with seconds should have 2 colons, got: \(timeString)")
    }

    // MARK: - Slider Offset Tests

    func testTimeWithPositiveSliderOffset() {
        let dataObject = TimezoneData(with: newYork)
        dataObject.setShouldOverrideGlobalTimeFormat(2) // 24-hour for easier parsing
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let currentTime = operations.time(with: 0)
        let futureTime = operations.time(with: 60) // 1 hour ahead

        XCTAssertFalse(currentTime.isEmpty)
        XCTAssertFalse(futureTime.isEmpty)
        // We can't easily compare times, but they should be different (unless wrapping around midnight)
        // Just verify no crash and non-empty
    }

    func testTimeWithNegativeSliderOffset() {
        let dataObject = TimezoneData(with: newYork)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let pastTime = operations.time(with: -60) // 1 hour behind
        XCTAssertFalse(pastTime.isEmpty, "Past time should not be empty")
    }

    func testTimeWithLargeSliderOffset() {
        let dataObject = TimezoneData(with: tokyo)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        // ±48 hours (2880 minutes) is the max slider range
        let farFuture = operations.time(with: 2880)
        let farPast = operations.time(with: -2880)

        XCTAssertFalse(farFuture.isEmpty, "Far future time should not be empty")
        XCTAssertFalse(farPast.isEmpty, "Far past time should not be empty")
    }

    // MARK: - Time Difference Tests

    func testTimeDifferenceSameTimezone() {
        let localTZ = TimeZone.autoupdatingCurrent.identifier
        let localData: [String: Any] = ["customLabel": "Local",
                                        "formattedAddress": "Local",
                                        "place_id": "TestLocal",
                                        "timezoneID": localTZ,
                                        "nextUpdate": "",
                                        "latitude": 0.0,
                                        "longitude": 0.0]
        let dataObject = TimezoneData(with: localData)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let diff = operations.timeDifference()
        XCTAssertEqual(diff, "", "Same timezone should have empty time difference")
    }

    func testTimeDifferenceAheadTimezone() {
        let dataObject = TimezoneData(with: tokyo)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let localTZ = TimeZone.autoupdatingCurrent
        let tokyoTZ = TimeZone(identifier: "Asia/Tokyo")!
        let diffSeconds = tokyoTZ.secondsFromGMT(for: Date()) - localTZ.secondsFromGMT(for: Date())

        let diff = operations.timeDifference()

        if diffSeconds == 0 {
            XCTAssertEqual(diff, "", "Same offset should have empty difference")
        } else if diffSeconds > 0 {
            XCTAssertTrue(diff.contains("+"), "Ahead timezone should contain '+' but got: \(diff)")
        } else {
            XCTAssertTrue(diff.contains("-"), "Behind timezone should contain '-' but got: \(diff)")
        }
    }

    func testTimeDifferenceBehindTimezone() {
        let dataObject = TimezoneData(with: newYork)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let diff = operations.timeDifference()

        let localTZ = TimeZone.autoupdatingCurrent
        let nyTZ = TimeZone(identifier: "America/New_York")!
        let diffSeconds = nyTZ.secondsFromGMT(for: Date()) - localTZ.secondsFromGMT(for: Date())

        if diffSeconds == 0 {
            XCTAssertEqual(diff, "", "Same offset should have empty difference")
        } else {
            XCTAssertFalse(diff.isEmpty, "Different timezone should have non-empty difference")
        }
    }

    // MARK: - Date Display Tests

    func testDateWithRelativeDayDisplay() {
        let dataObject = TimezoneData(with: newYork)
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 0)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let dateString = operations.date(with: 0, displayType: .panel)
        XCTAssertFalse(dateString.isEmpty, "Panel date display should not be empty")
    }

    func testDateWithDayNameDisplay() {
        let dataObject = TimezoneData(with: london)
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 1)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let dateString = operations.date(with: 0, displayType: .panel)
        XCTAssertFalse(dateString.isEmpty, "Day name display should not be empty")
    }

    func testDateWithDateFormatDisplay() {
        let dataObject = TimezoneData(with: tokyo)
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 2)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let dateString = operations.date(with: 0, displayType: .panel)
        XCTAssertFalse(dateString.isEmpty, "Date format display should not be empty")
    }

    func testDateWithHiddenDisplay() {
        let dataObject = TimezoneData(with: newYork)
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 3)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let dateString = operations.date(with: 0, displayType: .panel)
        XCTAssertEqual(dateString, "", "Hidden date display should return empty string")
    }

    func testDateWithMenuDisplayType() {
        let dataObject = TimezoneData(with: newYork)
        mockStore.preferences[UserDefaultKeys.relativeDateKey] = NSNumber(value: 0)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let dateString = operations.date(with: 0, displayType: .menu)
        XCTAssertFalse(dateString.isEmpty, "Menu date display should not be empty")
    }

    // MARK: - Sunrise/Sunset Tests

    func testFormattedSunriseTimeWithValidCoordinates() {
        let dataObject = TimezoneData(with: newYork)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let sunrise = operations.formattedSunriseTime(with: 0)
        XCTAssertFalse(sunrise.isEmpty, "Sunrise time should not be empty for location with coordinates")
        XCTAssertNotNil(dataObject.sunriseTime, "Sunrise time property should be set")
        XCTAssertNotNil(dataObject.sunsetTime, "Sunset time property should be set")
    }

    func testFormattedSunriseTimeWithNilCoordinates() {
        let dataObject = TimezoneData(with: noCoords)
        dataObject.selectionType = .timezone
        dataObject.latitude = nil
        dataObject.longitude = nil
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let sunrise = operations.formattedSunriseTime(with: 0)
        XCTAssertEqual(sunrise, "", "Sunrise time should be empty when coordinates are nil")
        XCTAssertNil(dataObject.sunriseTime, "Sunrise time property should be nil")
        XCTAssertNil(dataObject.sunsetTime, "Sunset time property should be nil")
    }

    func testFormattedSunsetTimeWithNilCoordinates() {
        let dataObject = TimezoneData(with: noCoords)
        dataObject.latitude = nil
        dataObject.longitude = nil
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let sunriseResult = operations.formattedSunriseTime(with: 0)
        XCTAssertEqual(sunriseResult, "", "Should return empty string when coordinates are nil")
    }

    // MARK: - DST Transition Tests

    func testNextDaylightSavingsTransitionForNonDSTTimezone() {
        // Asia/Tokyo does not observe DST
        let dataObject = TimezoneData(with: tokyo)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let transition = operations.nextDaylightSavingsTransitionIfAvailable(with: 0)
        XCTAssertNil(transition, "Tokyo should not have DST transitions")
    }

    func testNextDaylightSavingsTransitionFormat() {
        // America/New_York observes DST; transition may or may not be within 8 days
        let dataObject = TimezoneData(with: newYork)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let transition = operations.nextDaylightSavingsTransitionIfAvailable(with: 0)
        // Either nil (no upcoming transition within 8 days) or a properly formatted string
        if let transition = transition {
            XCTAssertTrue(transition.hasPrefix("Heads up:"), "DST message should start with 'Heads up:' but got: \(transition)")
            XCTAssertTrue(transition.contains("DST transition"), "DST message should contain 'DST transition'")
            // Also verify it contains a month name or year (not just a generic format check)
            let containsTimeInfo = transition.contains("AM") || transition.contains("PM") ||
                transition.contains(":") || transition.contains("2025") || transition.contains("2026")
            XCTAssertTrue(containsTimeInfo, "DST transition message should contain time information but got: \(transition)")
        }
    }

    // MARK: - Menu Title Tests

    func testMenuTitleWithDefaults() {
        let dataObject = TimezoneData(with: newYork)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let title = operations.menuTitle()
        XCTAssertFalse(title.isEmpty, "Menu title should not be empty")
    }

    func testMenuTitleWithCityShown() {
        let dataObject = TimezoneData(with: newYork)
        mockStore.viewTypeDisplayPreferences[.placeInMenubar] = true
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let title = operations.menuTitle()
        // When placeInMenubar is true, city name should appear
        XCTAssertTrue(title.contains("NYC") || title.contains("New York"),
                      "Menu title should contain city name but got: \(title)")
    }

    // MARK: - Compact Menu Title Tests

    func testCompactMenuTitle() {
        let dataObject = TimezoneData(with: tokyo)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let title = operations.compactMenuTitle()
        XCTAssertFalse(title.isEmpty, "Compact menu title should not be empty")
    }

    func testCompactMenuSubtitle() {
        let dataObject = TimezoneData(with: tokyo)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let subtitle = operations.compactMenuSubtitle()
        XCTAssertFalse(subtitle.isEmpty, "Compact menu subtitle should not be empty")
    }

    // MARK: - Today's Date Tests

    func testTodaysDate() {
        let dataObject = TimezoneData(with: london)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let dateStr = operations.todaysDate(with: 0)
        XCTAssertFalse(dateStr.isEmpty, "Today's date should not be empty")
    }

    func testTodaysDateWithLocale() {
        let dataObject = TimezoneData(with: london)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let germanLocale = Locale(identifier: "de_DE")
        let dateStr = operations.todaysDate(with: 0, locale: germanLocale)
        XCTAssertFalse(dateStr.isEmpty, "Today's date with German locale should not be empty")
    }

    // MARK: - Epoch Time Tests

    func testEpochTimeFormat() {
        let dataObject = TimezoneData(with: newYork)
        dataObject.setShouldOverrideGlobalTimeFormat(12) // epoch
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        let timeString = operations.time(with: 0)
        XCTAssertFalse(timeString.isEmpty, "Epoch time should not be empty")
        // Epoch time should be a numeric string
        let numericOnly = timeString.allSatisfy { $0.isNumber || $0 == "-" }
        XCTAssertTrue(numericOnly, "Epoch time should be numeric but got: \(timeString)")
    }
}
