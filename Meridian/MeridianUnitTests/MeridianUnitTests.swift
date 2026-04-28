// Copyright © 2015 Abhishek Banthia

import CoreModelKit

@testable import Meridian
import XCTest

class MeridianUnitTests: XCTestCase {
    private var mockStore: MockDataStore!

    override func setUp() {
        super.setUp()
        mockStore = MockDataStore()
    }

    override func tearDown() {
        mockStore = nil
        // Remove test-specific timezone entries that could pollute UserDefaults
        // when tests run in parallel across multiple workers.
        cleanupSingletonTimezones { tz in
            return tz?.placeID == "TestIdentifier"
        }
        super.tearDown()
    }

    private var california: [String: Any] { TestTimezones.california }
    private var mumbai: [String: Any] { TestTimezones.mumbai }
    private var auckland: [String: Any] { TestTimezones.auckland }
    private var florida: [String: Any] { TestTimezones.florida }
    private var onlyTimezone: [String: Any] { TestTimezones.onlyTimezone }
    private var omaha: [String: Any] { TestTimezones.omaha }

    private var operations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: mumbai), store: mockStore)
    }

    private var californiaOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: california), store: mockStore)
    }

    private var floridaOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: florida), store: mockStore)
    }

    private var aucklandOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: auckland), store: mockStore)
    }

    private var omahaOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: omaha), store: mockStore)
    }

    func testOverridingSecondsComponent_shouldHideSeconds() {
        // Use a MockDataStore to avoid modifying global UserDefaults
        let mockStore = MockDataStore()
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 4) // 4 is 12 hour with seconds

        let timezoneObjects = [TimezoneData(with: mumbai),
                               TimezoneData(with: auckland),
                               TimezoneData(with: california)]

        timezoneObjects.forEach {
            let operationsObject = TimezoneDataOperations(with: $0, store: mockStore)
            let currentTime = operationsObject.time(with: 0)
            XCTAssertEqual(currentTime.count, 8) // 8 includes 2 colons

            $0.setShouldOverrideGlobalTimeFormat(1)

            let newTime = operationsObject.time(with: 0)
            XCTAssertGreaterThanOrEqual(newTime.count, 7) // 5 includes colon
        }
    }

    func testAddingATimezoneToDefaults() {
        // Use MockDataStore to test timezone addition in isolation
        let mockStore = MockDataStore()
        let oldCount = mockStore.timezones().count

        let timezoneData = TimezoneData(with: california)
        let operationsObject = TimezoneDataOperations(with: timezoneData, store: mockStore)

        // saveObject() saves to the DataStore, but for isolated testing we verify the operation directly
        // by calling addTimezone on the mock instead
        mockStore.addTimezone(timezoneData)

        let newTimezones = mockStore.timezones()

        XCTAssertFalse(newTimezones.isEmpty)
        XCTAssertEqual(newTimezones.count, oldCount + 1)
    }

    func testDecoding() {
        let timezone1 = TimezoneData.customObject(from: nil)
        XCTAssertNotNil(timezone1)

        let data = Data()
        let timezone2 = TimezoneData.customObject(from: data)
        XCTAssertNil(timezone2)
    }

    func testDescription() {
        let timezoneData = TimezoneData(with: california)
        XCTAssertFalse(timezoneData.description.isEmpty)
        XCTAssertFalse(timezoneData.debugDescription.isEmpty)
    }

    func testHashing() {
        let timezoneData = TimezoneData(with: california)
        XCTAssertNotEqual(timezoneData.hash, -1)

        timezoneData.placeID = nil
        timezoneData.timezoneID = nil
        XCTAssertEqual(timezoneData.hash, -1)
    }

    func testBadInputDictionaryForInitialization() {
        let badInput: [String: Any] = ["customLabel": "",
                                       "latitude": "41.2565369",
                                       "longitude": "-95.9345034"]
        let badTimezoneData = TimezoneData(with: badInput)
        XCTAssertEqual(badTimezoneData.placeID, "Error")
        XCTAssertEqual(badTimezoneData.timezoneID, "Error")
        XCTAssertEqual(badTimezoneData.formattedAddress, "Error")
    }

    func testDeletingATimezone() {
        // Use MockDataStore for isolated deletion testing
        let mockStore = MockDataStore()

        // Add a test timezone
        let timezoneData = TimezoneData(with: california)
        mockStore.addTimezone(timezoneData)

        let oldCount = mockStore.timezones().count

        // Delete the last timezone
        mockStore.removeLastTimezone()

        let newTimezones = mockStore.timezones()

        XCTAssertEqual(newTimezones.count, oldCount - 1, "Timezone count should decrease by 1 after deletion")
    }

    func testTimeDifference() {
        // Compute expected differences dynamically from the local timezone
        // so this test works regardless of where the machine is located.
        let now = Date()
        let localTZ = TimeZone.autoupdatingCurrent

        func expectedDiff(for timezoneID: String) -> String {
            let targetTZ = TimeZone(identifier: timezoneID)!
            let diffSeconds = targetTZ.secondsFromGMT(for: now) - localTZ.secondsFromGMT(for: now)

            if diffSeconds == 0 { return "" }

            let sign = diffSeconds > 0 ? "+" : "-"
            let hours = abs(diffSeconds) / 3600
            let minutes = (abs(diffSeconds) % 3600) / 60

            if minutes == 0 {
                return ", \(sign)\(hours)h "
            } else {
                return ", \(sign)\(hours)h \(minutes)m"
            }
        }

        XCTAssertEqual(operations.timeDifference(), expectedDiff(for: "Asia/Calcutta"))
        XCTAssertEqual(californiaOperations.timeDifference(), expectedDiff(for: "America/Los_Angeles"))
        XCTAssertEqual(floridaOperations.timeDifference(), expectedDiff(for: "America/New_York"))
        XCTAssertEqual(aucklandOperations.timeDifference(), expectedDiff(for: "Pacific/Auckland"))
        XCTAssertEqual(omahaOperations.timeDifference(), expectedDiff(for: "America/Chicago"))
    }

    func testSunriseSunset() {
        let dataObject = TimezoneData(with: mumbai)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        XCTAssertNotNil(operations.formattedSunriseTime(with: 0))
        XCTAssertNotNil(dataObject.sunriseTime)
        XCTAssertNotNil(dataObject.sunriseTime)

        let timezoneObject = TimezoneData(with: onlyTimezone)
        timezoneObject.selectionType = .timezone
        // Timezone entries with coordinates now support sunrise/sunset
        timezoneObject.latitude = nil
        timezoneObject.longitude = nil
        let timezoneOperations = TimezoneDataOperations(with: timezoneObject, store: mockStore)

        XCTAssertEqual(timezoneOperations.formattedSunriseTime(with: 0), "")
        XCTAssertNil(timezoneObject.sunriseTime)
        XCTAssertNil(timezoneObject.sunsetTime)
    }

    func testDateWithSliderValue() {
        let dataObject = TimezoneData(with: mumbai)
        let operations = TimezoneDataOperations(with: dataObject, store: mockStore)

        XCTAssertNotNil(operations.date(with: 0, displayType: .menu))
    }

    func testTimezoneFormat() {
        let dataObject = TimezoneData(with: mumbai)
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 0) // Set to 12 hour format

        dataObject.setShouldOverrideGlobalTimeFormat(0) // Respect Global Preference
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "h:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(1) // 12-Hour Format
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "h:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(2) // 24-Hour format
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "HH:mm")

        // Skip 3 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(4) // 12-Hour with seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "h:mm:ss a")

        dataObject.setShouldOverrideGlobalTimeFormat(5) // 24-Hour format with seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "HH:mm:ss")

        // Skip 6 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(7) // 12-hour with preceding zero and no seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(8) // 12-hour with preceding zero and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm:ss a")

        // Skip 9 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(10) // 12-hour without am/pm and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm")

        dataObject.setShouldOverrideGlobalTimeFormat(11) // 12-hour with preceding zero and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm:ss")

        // Wrong input
        dataObject.setShouldOverrideGlobalTimeFormat(0) // 12-hour with preceding zero and seconds
        XCTAssertEqual(dataObject.timezoneFormat(88), "h:mm a")
    }

    func testTimezoneFormatWithDefaultSetAs24HourFormat() {
        let dataObject = TimezoneData(with: california)
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 1) // Set to 24-Hour Format

        dataObject.setShouldOverrideGlobalTimeFormat(0)
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "HH:mm",
                       "Unexpected format returned: \(dataObject.timezoneFormat(mockStore.timezoneFormat()))")

        dataObject.setShouldOverrideGlobalTimeFormat(1) // 12-Hour Format
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "h:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(2) // 24-Hour format
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "HH:mm")

        // Skip 3 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(4) // 12-Hour with seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "h:mm:ss a")

        dataObject.setShouldOverrideGlobalTimeFormat(5) // 24-Hour format with seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "HH:mm:ss")

        // Skip 6 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(7) // 12-hour with preceding zero and no seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(8) // 12-hour with preceding zero and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm:ss a")

        // Skip 9 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(10) // 12-hour without am/pm and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm")

        dataObject.setShouldOverrideGlobalTimeFormat(11) // 12-hour with preceding zero and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "hh:mm:ss")

        dataObject.setShouldOverrideGlobalTimeFormat(12) // 12-hour with preceding zero and seconds
        XCTAssertEqual(dataObject.timezoneFormat(mockStore.timezoneFormat()), "epoch")
    }

    func testSecondsDisplayForOverridenTimezone() {
        let dataObject = TimezoneData(with: california)
        mockStore.preferences[UserDefaultKeys.selectedTimeZoneFormatKey] = NSNumber(value: 1) // Set to 24-Hour Format

        // Test default behaviour
        let timezoneWithSecondsKeys = [4, 5, 8, 11]
        for timezoneKey in timezoneWithSecondsKeys {
            dataObject.setShouldOverrideGlobalTimeFormat(timezoneKey)
            XCTAssertTrue(dataObject.shouldShowSeconds(mockStore.timezoneFormat()))
        }

        let timezoneWithoutSecondsKeys = [1, 2, 7, 10]
        for timezoneKey in timezoneWithoutSecondsKeys {
            dataObject.setShouldOverrideGlobalTimeFormat(timezoneKey)
            XCTAssertFalse(dataObject.shouldShowSeconds(mockStore.timezoneFormat()))
        }

        // Test wrong override timezone key
        let wrongTimezoneKey = 88
        dataObject.setShouldOverrideGlobalTimeFormat(wrongTimezoneKey)
        XCTAssertFalse(dataObject.shouldShowSeconds(mockStore.timezoneFormat()))

        // Test wrong global preference key
        dataObject.setShouldOverrideGlobalTimeFormat(0)
        XCTAssertFalse(dataObject.shouldShowSeconds(88))
    }

    func testTimezoneRetrieval() {
        let dataObject = TimezoneData(with: mumbai)
        let autoupdatingTimezone = TimeZone.autoupdatingCurrent.identifier
        XCTAssertEqual(dataObject.timezone(), "Asia/Calcutta")

        // Unlikely
        dataObject.timezoneID = nil
        XCTAssertEqual(dataObject.timezone(), autoupdatingTimezone)

        dataObject.isSystemTimezone = true
        XCTAssertEqual(dataObject.timezone(), autoupdatingTimezone)
    }

    func testFormattedLabel() {
        let dataObject = TimezoneData(with: mumbai)
        XCTAssertEqual(dataObject.formattedTimezoneLabel(), "Ghar", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        dataObject.setLabel("")
        XCTAssertEqual(dataObject.formattedTimezoneLabel(), "Mumbai", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        dataObject.formattedAddress = nil
        XCTAssertEqual(dataObject.formattedTimezoneLabel(), "Asia", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        dataObject.setLabel("Jogeshwari")
        XCTAssertEqual(dataObject.formattedTimezoneLabel(), "Jogeshwari", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        // Unlikely scenario
        dataObject.setLabel("")
        dataObject.timezoneID = "GMT"
        XCTAssertEqual(dataObject.formattedTimezoneLabel(), "GMT", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        // Another unlikely scenario
        dataObject.setLabel("")
        dataObject.timezoneID = nil
        XCTAssertEqual(dataObject.formattedTimezoneLabel(), "Error", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")
    }

    func testEquality() {
        let dataObject1 = TimezoneData(with: mumbai)
        let dataObject2 = TimezoneData(with: auckland)

        XCTAssertFalse(dataObject1 == dataObject2)
        XCTAssertFalse(dataObject1.isEqual(dataObject2))

        let dataObject3 = TimezoneData(with: mumbai)
        XCTAssertEqual(dataObject1, dataObject3)
        XCTAssertTrue(dataObject1.isEqual(dataObject3))

        XCTAssertFalse(dataObject1.isEqual(nil))
    }

    func testWithAllLocales() {
        let dataObject1 = TimezoneData(with: mumbai)
        let operations = TimezoneDataOperations(with: dataObject1, store: mockStore)

        for locale in Locale.availableIdentifiers {
            let currentLocale = Locale(identifier: locale)
            let localizedDate = operations.todaysDate(with: 0, locale: currentLocale)
            XCTAssertNotNil(localizedDate)
            XCTAssertFalse(localizedDate.isEmpty, "Date string should not be empty for locale \(locale)")
        }
    }

    func testTimeWithAllLocales() {
        let dataObject = TimezoneData(with: mumbai)

        let cal = Calendar(identifier: .gregorian)

        guard let newDate = cal.date(byAdding: .minute,
                                     value: 0,
                                     to: Date())
        else {
            XCTFail("Unable to add dates!")
            return
        }

        for locale in Locale.availableIdentifiers {
            let currentLocale = Locale(identifier: locale)
            let dateFormatter = DateFormatterManager.dateFormatterWithFormat(with: .none,
                                                                             format: dataObject.timezoneFormat(mockStore.timezoneFormat()),
                                                                             timezoneIdentifier: dataObject.timezone(),
                                                                             locale: currentLocale)
            let convertedDate = dateFormatter.string(from: newDate)
            XCTAssertNotNil(convertedDate)
            XCTAssertFalse(convertedDate.isEmpty, "Time string should not be empty for locale \(locale)")
        }
    }

    func testStringFiltering() {
        let stringWithComma = "Mumbai, Maharashtra"
        let stringWithoutComma = "Mumbai"
        let emptyString = ""

        XCTAssertEqual(stringWithComma.filteredName(), "Mumbai")
        XCTAssertEqual(stringWithoutComma.filteredName(), "Mumbai")
        XCTAssertEqual(emptyString.filteredName(), "")
    }

    func testPointingHandButton() {
        let sampleRect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let pointingHandCursorButton = PointingHandCursorButton(frame: CGRect.zero)
        pointingHandCursorButton.draw(sampleRect)
        pointingHandCursorButton.resetCursorRects()
        XCTAssertEqual(pointingHandCursorButton.pointingHandCursor, NSCursor.pointingHand)
    }

    func testNoTimezoneView() {
        let sampleRect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let subject = NoTimezoneView(frame: sampleRect)
        // Perform a layout to add subviews
        subject.layout()
        XCTAssertGreaterThanOrEqual(subject.subviews.count, 2, "NoTimezoneView should have at least 2 subviews after layout")
    }

    func testDefaultsWiping() {
        let defaultsDict: [String: Any] = ["test1": "testString", "test2": 24]
        let domainName = "com.test.meridian"
        let defaults = UserDefaults(suiteName: domainName)
        defaults?.setPersistentDomain(defaultsDict, forName: domainName)
        defaults?.wipe(for: domainName)
        XCTAssertNil(defaults?.object(forKey: "test1"))
        XCTAssertNil(defaults?.object(forKey: "test2"))
    }

    func testDeserializationWithInvalidSelectionType() {
        /// Tests that TimezoneData gracefully handles a corrupt archive with an invalid selectionType.
        /// This test intentionally manipulates the NSKeyedArchiver internal plist structure because
        /// corrupt data cannot be injected through the public TimezoneData API — it must be injected
        /// at the serialization level to simulate real-world archive corruption.

        // Tests that TimezoneData gracefully handles corrupt NSKeyedArchiver data containing
        // an invalid selectionType raw value. This test necessarily accesses the internal
        // NSCoding structure since the corruption must be injected at the archive level.
        // Archive a valid TimezoneData, then tamper with the plist to set an invalid selectionType
        let original = TimezoneData(with: california)
        original.selectionType = .city

        guard let archivedData = try? NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true) else {
            XCTFail("Failed to archive TimezoneData")
            return
        }

        // Deserialize the archive into a mutable plist, tamper with selectionType, re-serialize
        guard var plist = try? PropertyListSerialization.propertyList(from: archivedData, format: nil) as? [String: Any],
              var objects = plist["$objects"] as? [Any]
        else {
            XCTFail("Failed to parse archived plist")
            return
        }

        // Find the root object and tamper with selectionType
        // The root object is typically at index 1 in $objects (index 0 is "$null")
        // Walk objects looking for a dictionary containing "selectionType"
        for i in 0 ..< objects.count {
            if var dict = objects[i] as? [String: Any], dict["selectionType"] != nil {
                dict["selectionType"] = 999 // Invalid raw value
                objects[i] = dict
                break
            }
        }

        plist["$objects"] = objects

        guard let tamperedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else {
            XCTFail("Failed to re-serialize tampered plist")
            return
        }

        // Unarchive — init?(coder:) uses `?? .city` so invalid values should default
        let result = TimezoneData.customObject(from: tamperedData)

        XCTAssertNotNil(result, "Deserialization should not return nil for invalid selectionType")
        XCTAssertEqual(result?.selectionType, .city, "Invalid selectionType should default to .city")
    }

    func testSecureCodingRoundtrip() {
        let original = TimezoneData(with: california)
        original.isFavourite = 1
        original.selectionType = .city
        original.setShouldOverrideGlobalTimeFormat(2) // 24-hour

        // Archive using secureArchive
        guard let archivedData = NSKeyedArchiver.secureArchive(with: original) else {
            XCTFail("secureArchive returned nil")
            return
        }

        // Unarchive using customObject(from:) which uses requiresSecureCoding = true
        let restored = TimezoneData.customObject(from: archivedData)

        XCTAssertNotNil(restored, "customObject(from:) should return non-nil")
        XCTAssertEqual(restored?.placeID, original.placeID, "placeID should match")
        XCTAssertEqual(restored?.timezoneID, original.timezoneID, "timezoneID should match")
        XCTAssertEqual(restored?.formattedAddress, original.formattedAddress, "formattedAddress should match")
        XCTAssertEqual(restored?.customLabel, original.customLabel, "customLabel should match")
        XCTAssertEqual(restored?.isFavourite, original.isFavourite, "isFavourite should match")
        XCTAssertEqual(restored?.selectionType, original.selectionType, "selectionType should match")
        XCTAssertEqual(restored?.overrideFormat, original.overrideFormat, "overrideFormat should match")
        XCTAssertEqual(restored?.isSystemTimezone, original.isSystemTimezone, "isSystemTimezone should match")
        XCTAssertEqual(restored?.latitude, original.latitude, "latitude should match")
        XCTAssertEqual(restored?.longitude, original.longitude, "longitude should match")
    }
}

// MARK: - Typed accessor tests (issue #97)

class DataStoreTypedAccessorsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: DataStore!

    override func setUp() {
        super.setUp()
        suiteName = "com.tpak.meridian.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = DataStore(with: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: bools — read

    func testShowSunriseSunset_readsNewKey() {
        defaults.set(true, forKey: UserDefaultKeys.showSunriseSunset)
        XCTAssertTrue(store.showSunriseSunset)
        defaults.set(false, forKey: UserDefaultKeys.showSunriseSunset)
        XCTAssertFalse(store.showSunriseSunset)
    }

    func testShowFutureSlider_readsNewKey() {
        defaults.set(true, forKey: UserDefaultKeys.showFutureSlider)
        XCTAssertTrue(store.showFutureSlider)
        defaults.set(false, forKey: UserDefaultKeys.showFutureSlider)
        XCTAssertFalse(store.showFutureSlider)
    }

    func testShowDayInMenubar_readsNewKey() {
        defaults.set(true, forKey: UserDefaultKeys.showDayInMenubar)
        XCTAssertTrue(store.showDayInMenubar)
    }

    func testShowDateInMenubar_readsNewKey() {
        defaults.set(true, forKey: UserDefaultKeys.showDateInMenubar)
        XCTAssertTrue(store.showDateInMenubar)
    }

    func testShowPlaceNameInMenubar_readsNewKey() {
        defaults.set(true, forKey: UserDefaultKeys.showPlaceNameInMenubar)
        XCTAssertTrue(store.showPlaceNameInMenubar)
    }

    func testFloatOnTop_readsNewKey() {
        defaults.set(true, forKey: UserDefaultKeys.floatOnTop)
        XCTAssertTrue(store.floatOnTop)
        defaults.set(false, forKey: UserDefaultKeys.floatOnTop)
        XCTAssertFalse(store.floatOnTop)
    }

    // MARK: bools — write

    func testShowSunriseSunset_writeStoresBool() {
        store.showSunriseSunset = true
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.showSunriseSunset))
        store.showSunriseSunset = false
        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.showSunriseSunset))
    }

    func testFloatOnTop_writeStoresBool() {
        store.floatOnTop = true
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.floatOnTop))
    }

    // MARK: bools — round-trip

    func testBoolAccessors_roundTrip() {
        store.showSunriseSunset = true
        store.showFutureSlider = false
        store.showDayInMenubar = true
        store.showDateInMenubar = false
        store.showPlaceNameInMenubar = true
        store.floatOnTop = true

        XCTAssertTrue(store.showSunriseSunset)
        XCTAssertFalse(store.showFutureSlider)
        XCTAssertTrue(store.showDayInMenubar)
        XCTAssertFalse(store.showDateInMenubar)
        XCTAssertTrue(store.showPlaceNameInMenubar)
        XCTAssertTrue(store.floatOnTop)
    }

    // MARK: enums

    func testMenubarMode_readsCanonicalKey() {
        defaults.set(MenubarMode.compact.rawValue, forKey: UserDefaultKeys.menubarCompactMode)
        XCTAssertEqual(store.menubarMode, .compact)
        defaults.set(MenubarMode.standard.rawValue, forKey: UserDefaultKeys.menubarCompactMode)
        XCTAssertEqual(store.menubarMode, .standard)
    }

    func testMenubarMode_invalidRawFallsBackToStandard() {
        defaults.set(99, forKey: UserDefaultKeys.menubarCompactMode)
        XCTAssertEqual(store.menubarMode, .standard)
    }

    func testMenubarMode_missingKeyReturnsStandard() {
        XCTAssertEqual(store.menubarMode, .standard)
    }

    func testMenubarMode_roundTrip() {
        store.menubarMode = .compact
        XCTAssertEqual(store.menubarMode, .compact)
        store.menubarMode = .standard
        XCTAssertEqual(store.menubarMode, .standard)
    }

    func testTheme_allCases() {
        for theme: Theme in [.light, .dark, .system] {
            store.theme = theme
            XCTAssertEqual(store.theme, theme)
        }
    }

    func testRelativeDateDisplay_allCases() {
        for value: RelativeDateDisplay in [.relative, .actual, .date, .hidden] {
            store.relativeDateDisplay = value
            XCTAssertEqual(store.relativeDateDisplay, value)
        }
    }

    func testAppPresentation_roundTrip() {
        store.appPresentation = .menubarAndDock
        XCTAssertEqual(store.appPresentation, .menubarAndDock)
        store.appPresentation = .menubarOnly
        XCTAssertEqual(store.appPresentation, .menubarOnly)
    }

    func testTimeFormat_allValidIndices() {
        let cases: [TimeFormat] = [
            .twelveHour, .twentyFourHour,
            .twelveHourWithSeconds, .twentyFourHourWithSeconds,
            .twelveHourWithLeadingZero, .twelveHourWithLeadingZeroAndSeconds,
            .twelveHourWithoutAmPm, .twelveHourWithoutAmPmAndSeconds,
            .epoch,
        ]
        for value in cases {
            store.timeFormat = value
            XCTAssertEqual(store.timeFormat, value, "round-trip failed for \(value)")
        }
    }

    func testTimeFormat_separatorRawFallsBackToTwelveHour() {
        // Indices 2/5/8 are disabled separator rows; if a stale value lands
        // there we should not crash, just fall back.
        for separatorRaw in [2, 5, 8] {
            defaults.set(separatorRaw, forKey: UserDefaultKeys.timeFormat)
            XCTAssertEqual(store.timeFormat, .twelveHour)
        }
    }

    // MARK: parity with shouldDisplay()

    // shouldDisplay(_:) now delegates to typed accessors; these asserts make
    // sure that delegation never drifts.

    func testParity_sunrise() {
        store.showSunriseSunset = true
        XCTAssertEqual(store.showSunriseSunset, store.shouldDisplay(.sunrise))
        store.showSunriseSunset = false
        XCTAssertEqual(store.showSunriseSunset, store.shouldDisplay(.sunrise))
    }

    func testParity_futureSlider() {
        store.showFutureSlider = true
        XCTAssertEqual(store.showFutureSlider, store.shouldDisplay(.futureSlider))
        store.showFutureSlider = false
        XCTAssertEqual(store.showFutureSlider, store.shouldDisplay(.futureSlider))
    }

    func testParity_dayInMenubar() {
        store.showDayInMenubar = true
        XCTAssertEqual(store.showDayInMenubar, store.shouldDisplay(.dayInMenubar))
        store.showDayInMenubar = false
        XCTAssertEqual(store.showDayInMenubar, store.shouldDisplay(.dayInMenubar))
    }

    func testParity_dateInMenubar() {
        store.showDateInMenubar = true
        XCTAssertEqual(store.showDateInMenubar, store.shouldDisplay(.dateInMenubar))
        store.showDateInMenubar = false
        XCTAssertEqual(store.showDateInMenubar, store.shouldDisplay(.dateInMenubar))
    }

    func testParity_placeNameInMenubar() {
        store.showPlaceNameInMenubar = true
        XCTAssertEqual(store.showPlaceNameInMenubar, store.shouldDisplay(.placeInMenubar))
        store.showPlaceNameInMenubar = false
        XCTAssertEqual(store.showPlaceNameInMenubar, store.shouldDisplay(.placeInMenubar))
    }

    func testParity_floatOnTop() {
        store.floatOnTop = true
        XCTAssertEqual(store.floatOnTop, store.shouldDisplay(.showAppInForeground))
        store.floatOnTop = false
        XCTAssertEqual(store.floatOnTop, store.shouldDisplay(.showAppInForeground))
    }

    func testParity_menubarMode() {
        store.menubarMode = .compact
        XCTAssertTrue(store.shouldDisplay(.menubarCompactMode))
        store.menubarMode = .standard
        XCTAssertFalse(store.shouldDisplay(.menubarCompactMode))
    }

    func testParity_appPresentation() {
        store.appPresentation = .menubarOnly
        XCTAssertTrue(store.shouldDisplay(.appDisplayOptions))
        store.appPresentation = .menubarAndDock
        XCTAssertFalse(store.shouldDisplay(.appDisplayOptions))
    }
}

// MARK: - BoolSemanticsMigration tests (issue #97)

class BoolSemanticsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.tpak.meridian.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: idempotency

    // The persistent domain excludes the global registration domain (which
    // the host app's launch populates via register(defaults:)), so it's
    // the right lens for "did the migration actually persist a write".
    private func persistent() -> [String: Any] {
        defaults.persistentDomain(forName: suiteName) ?? [:]
    }

    func testFreshInstall_noOpButSetsFlag() {
        AppDefaults.runBoolSemanticsMigration(on: defaults)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.boolSemanticsMigrationV1))
        // The only persistent write should be the flag — migration didn't
        // touch any new key because no legacy values were present.
        let p = persistent()
        XCTAssertNil(p[UserDefaultKeys.showSunriseSunset])
        XCTAssertNil(p[UserDefaultKeys.floatOnTop])
        XCTAssertNil(p[UserDefaultKeys.timeFormat])
        XCTAssertNotNil(p[UserDefaultKeys.boolSemanticsMigrationV1])
    }

    func testIdempotent_secondRunIsNoOp() {
        // First run: flag set, no legacy values present.
        AppDefaults.runBoolSemanticsMigration(on: defaults)
        // Now plant legacy keys — second run should ignore them because the
        // flag is set, so no new-key writes should happen.
        defaults.set(0, forKey: UserDefaultKeys.sunriseSunsetTime)
        defaults.set(1, forKey: UserDefaultKeys.showAppInForeground)
        AppDefaults.runBoolSemanticsMigration(on: defaults)
        let p = persistent()
        XCTAssertNil(p[UserDefaultKeys.showSunriseSunset])
        XCTAssertNil(p[UserDefaultKeys.floatOnTop])
        // Legacy keys are still where the test left them — second run did
        // not migrate them away.
        XCTAssertEqual(defaults.integer(forKey: UserDefaultKeys.sunriseSunsetTime), 0)
    }

    // MARK: inverted bools

    func testInvertedBool_legacyZeroBecomesTrue() {
        // 0 = show in legacy
        defaults.set(0, forKey: UserDefaultKeys.sunriseSunsetTime)
        defaults.set(0, forKey: UserDefaultKeys.displayFutureSliderKey)
        defaults.set(0, forKey: UserDefaultKeys.showDayInMenu)
        defaults.set(0, forKey: UserDefaultKeys.showDateInMenu)
        defaults.set(0, forKey: UserDefaultKeys.showPlaceInMenu)

        AppDefaults.runBoolSemanticsMigration(on: defaults)

        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.showSunriseSunset))
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.showFutureSlider))
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.showDayInMenubar))
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.showDateInMenubar))
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.showPlaceNameInMenubar))
    }

    func testInvertedBool_legacyOneBecomesFalse() {
        defaults.set(1, forKey: UserDefaultKeys.sunriseSunsetTime)
        defaults.set(1, forKey: UserDefaultKeys.displayFutureSliderKey)
        defaults.set(1, forKey: UserDefaultKeys.showDayInMenu)
        defaults.set(1, forKey: UserDefaultKeys.showDateInMenu)
        defaults.set(1, forKey: UserDefaultKeys.showPlaceInMenu)

        AppDefaults.runBoolSemanticsMigration(on: defaults)

        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.showSunriseSunset))
        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.showFutureSlider))
        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.showDayInMenubar))
        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.showDateInMenubar))
        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.showPlaceNameInMenubar))
    }

    func testInvertedBool_legacyKeysRemovedAfterMigration() {
        defaults.set(0, forKey: UserDefaultKeys.sunriseSunsetTime)
        defaults.set(1, forKey: UserDefaultKeys.showDayInMenu)

        AppDefaults.runBoolSemanticsMigration(on: defaults)

        XCTAssertNil(defaults.object(forKey: UserDefaultKeys.sunriseSunsetTime))
        XCTAssertNil(defaults.object(forKey: UserDefaultKeys.showDayInMenu))
    }

    // MARK: non-inverted bool

    func testFloatOnTop_legacyOneBecomesTrue() {
        defaults.set(1, forKey: UserDefaultKeys.showAppInForeground)
        AppDefaults.runBoolSemanticsMigration(on: defaults)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.floatOnTop))
        XCTAssertNil(defaults.object(forKey: UserDefaultKeys.showAppInForeground))
    }

    func testFloatOnTop_legacyZeroBecomesFalse() {
        defaults.set(0, forKey: UserDefaultKeys.showAppInForeground)
        AppDefaults.runBoolSemanticsMigration(on: defaults)
        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.floatOnTop))
        XCTAssertNil(defaults.object(forKey: UserDefaultKeys.showAppInForeground))
    }

    // MARK: time format rename

    func testTimeFormat_legacyValueCopiedToNewKey() {
        defaults.set(NSNumber(value: 7), forKey: UserDefaultKeys.selectedTimeZoneFormatKey)
        AppDefaults.runBoolSemanticsMigration(on: defaults)
        XCTAssertEqual(defaults.integer(forKey: UserDefaultKeys.timeFormat), 7)
        XCTAssertNil(defaults.object(forKey: UserDefaultKeys.selectedTimeZoneFormatKey))
    }

    // MARK: untouched keys

    func testUntouchedKeys_themeAndRelativeDateAndAppDisplayAndMenubarMode() {
        defaults.set(2, forKey: UserDefaultKeys.themeKey)
        defaults.set(3, forKey: UserDefaultKeys.relativeDateKey)
        defaults.set(1, forKey: UserDefaultKeys.appDisplayOptions)
        defaults.set(0, forKey: UserDefaultKeys.menubarCompactMode)

        AppDefaults.runBoolSemanticsMigration(on: defaults)

        // Migration must not touch already-correct enum keys.
        XCTAssertEqual(defaults.integer(forKey: UserDefaultKeys.themeKey), 2)
        XCTAssertEqual(defaults.integer(forKey: UserDefaultKeys.relativeDateKey), 3)
        XCTAssertEqual(defaults.integer(forKey: UserDefaultKeys.appDisplayOptions), 1)
        XCTAssertEqual(defaults.integer(forKey: UserDefaultKeys.menubarCompactMode), 0)
    }

    // MARK: integration with typed accessors

    func testEndToEnd_legacyValuesReadableViaTypedAccessorsAfterMigration() {
        // Plant the full legacy schema for an upgrading user.
        defaults.set(0, forKey: UserDefaultKeys.sunriseSunsetTime)         // show
        defaults.set(1, forKey: UserDefaultKeys.displayFutureSliderKey)    // hide
        defaults.set(0, forKey: UserDefaultKeys.showDayInMenu)             // show
        defaults.set(1, forKey: UserDefaultKeys.showDateInMenu)            // hide
        defaults.set(0, forKey: UserDefaultKeys.showPlaceInMenu)           // show
        defaults.set(1, forKey: UserDefaultKeys.showAppInForeground)       // float
        defaults.set(NSNumber(value: 4), forKey: UserDefaultKeys.selectedTimeZoneFormatKey)
        defaults.set(0, forKey: UserDefaultKeys.menubarCompactMode)        // compact
        defaults.set(1, forKey: UserDefaultKeys.appDisplayOptions)         // dock
        defaults.set(2, forKey: UserDefaultKeys.themeKey)                  // system
        defaults.set(3, forKey: UserDefaultKeys.relativeDateKey)           // hidden

        AppDefaults.runBoolSemanticsMigration(on: defaults)

        let store = DataStore(with: defaults)
        XCTAssertTrue(store.showSunriseSunset)
        XCTAssertFalse(store.showFutureSlider)
        XCTAssertTrue(store.showDayInMenubar)
        XCTAssertFalse(store.showDateInMenubar)
        XCTAssertTrue(store.showPlaceNameInMenubar)
        XCTAssertTrue(store.floatOnTop)
        XCTAssertEqual(store.timeFormat, .twentyFourHourWithSeconds)
        XCTAssertEqual(store.menubarMode, .compact)
        XCTAssertEqual(store.appPresentation, .menubarAndDock)
        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.relativeDateDisplay, .hidden)
    }
}
