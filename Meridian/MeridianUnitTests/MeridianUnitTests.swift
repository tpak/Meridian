// Copyright © 2015 Abhishek Banthia

import CoreModelKit

@testable import Meridian
import XCTest

class MeridianUnitTests: XCTestCase {
    override func tearDown() {
        // Remove test-specific timezone entries that could pollute UserDefaults
        // when tests run in parallel across multiple workers.
        let cleaned = DataStore.shared().timezones().filter {
            let tz = TimezoneData.customObject(from: $0)
            return tz?.placeID != "TestIdentifier"
        }
        DataStore.shared().setTimezones(cleaned)
        super.tearDown()
    }

    private var california: [String: Any] { TestTimezones.california }
    private var mumbai: [String: Any] { TestTimezones.mumbai }
    private var auckland: [String: Any] { TestTimezones.auckland }
    private var florida: [String: Any] { TestTimezones.florida }
    private var onlyTimezone: [String: Any] { TestTimezones.onlyTimezone }
    private var omaha: [String: Any] { TestTimezones.omaha }

    private var operations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: mumbai), store: DataStore.shared())
    }

    private var californiaOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: california), store: DataStore.shared())
    }

    private var floridaOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: florida), store: DataStore.shared())
    }

    private var aucklandOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: auckland), store: DataStore.shared())
    }

    private var omahaOperations: TimezoneDataOperations {
        return TimezoneDataOperations(with: TimezoneData(with: omaha), store: DataStore.shared())
    }

    func testOverridingSecondsComponent_shouldHideSeconds() {
        let dummyDefaults = UserDefaults.standard
        dummyDefaults.set(NSNumber(value: 4), forKey: UserDefaultKeys.selectedTimeZoneFormatKey) // 4 is 12 hour with seconds

        let timezoneObjects = [TimezoneData(with: mumbai),
                               TimezoneData(with: auckland),
                               TimezoneData(with: california)]

        timezoneObjects.forEach {
            let operationsObject = TimezoneDataOperations(with: $0, store: DataStore.shared())
            let currentTime = operationsObject.time(with: 0)
            XCTAssert(currentTime.count == 8) // 8 includes 2 colons

            $0.setShouldOverrideGlobalTimeFormat(1)

            let newTime = operationsObject.time(with: 0)
            XCTAssert(newTime.count >= 7) // 5 includes colon
        }
    }

    func testAddingATimezoneToDefaults() {
        let currentFavourites = DataStore.shared().timezones()
        defer { DataStore.shared().setTimezones(currentFavourites) }

        let timezoneData = TimezoneData(with: california)
        let oldCount = currentFavourites.count

        let operationsObject = TimezoneDataOperations(with: timezoneData, store: DataStore.shared())
        operationsObject.saveObject()

        let newDefaults = DataStore.shared().timezones()

        XCTAssert(newDefaults.isEmpty == false)
        XCTAssert(newDefaults.count == oldCount + 1)
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
        XCTAssert(timezoneData.hash != -1)

        timezoneData.placeID = nil
        timezoneData.timezoneID = nil
        XCTAssert(timezoneData.hash == -1)
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
        let originalFavourites = DataStore.shared().timezones()
        defer { DataStore.shared().setTimezones(originalFavourites) }

        // Always add the test timezone so this test is self-contained
        let timezoneData = TimezoneData(with: california)
        let operationsObject = TimezoneDataOperations(with: timezoneData, store: DataStore.shared())
        operationsObject.saveObject()

        let oldCount = DataStore.shared().timezones().count

        let currentFavourites = DataStore.shared().timezones().filter {
            let timezone = TimezoneData.customObject(from: $0)
            return timezone?.placeID != "TestIdentifier"
        }

        DataStore.shared().setTimezones(currentFavourites)

        XCTAssertTrue(currentFavourites.count == oldCount - 1, "Current Favourites Count \(currentFavourites.count) and Old Count \(oldCount - 1) don't line up.")
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
        let operations = TimezoneDataOperations(with: dataObject, store: DataStore.shared())

        XCTAssertNotNil(operations.formattedSunriseTime(with: 0))
        XCTAssertNotNil(dataObject.sunriseTime)
        XCTAssertNotNil(dataObject.sunriseTime)

        let timezoneObject = TimezoneData(with: onlyTimezone)
        timezoneObject.selectionType = .timezone
        // Timezone entries with coordinates now support sunrise/sunset
        timezoneObject.latitude = nil
        timezoneObject.longitude = nil
        let timezoneOperations = TimezoneDataOperations(with: timezoneObject, store: DataStore.shared())

        XCTAssertTrue(timezoneOperations.formattedSunriseTime(with: 0) == "")
        XCTAssertNil(timezoneObject.sunriseTime)
        XCTAssertNil(timezoneObject.sunsetTime)
    }

    func testDateWithSliderValue() {
        let dataObject = TimezoneData(with: mumbai)
        let operations = TimezoneDataOperations(with: dataObject, store: DataStore.shared())

        XCTAssertNotNil(operations.date(with: 0, displayType: .menu))
    }

    func testTimezoneFormat() {
        let dataObject = TimezoneData(with: mumbai)
        UserDefaults.standard.set(NSNumber(value: 0), forKey: UserDefaultKeys.selectedTimeZoneFormatKey) // Set to 12 hour format

        dataObject.setShouldOverrideGlobalTimeFormat(0) // Respect Global Preference
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "h:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(1) // 12-Hour Format
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "h:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(2) // 24-Hour format
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "HH:mm")

        // Skip 3 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(4) // 12-Hour with seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "h:mm:ss a")

        dataObject.setShouldOverrideGlobalTimeFormat(5) // 24-Hour format with seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "HH:mm:ss")

        // Skip 6 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(7) // 12-hour with preceding zero and no seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(8) // 12-hour with preceding zero and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm:ss a")

        // Skip 9 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(10) // 12-hour without am/pm and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm")

        dataObject.setShouldOverrideGlobalTimeFormat(11) // 12-hour with preceding zero and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm:ss")

        // Wrong input
        dataObject.setShouldOverrideGlobalTimeFormat(0) // 12-hour with preceding zero and seconds
        XCTAssertTrue(dataObject.timezoneFormat(88) == "h:mm a")
    }

    func testTimezoneFormatWithDefaultSetAs24HourFormat() {
        let dataObject = TimezoneData(with: california)
        UserDefaults.standard.set(NSNumber(value: 1), forKey: UserDefaultKeys.selectedTimeZoneFormatKey) // Set to 24-Hour Format

        dataObject.setShouldOverrideGlobalTimeFormat(0)
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "HH:mm",
                      "Unexpected format returned: \(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()))")

        dataObject.setShouldOverrideGlobalTimeFormat(1) // 12-Hour Format
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "h:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(2) // 24-Hour format
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "HH:mm")

        // Skip 3 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(4) // 12-Hour with seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "h:mm:ss a")

        dataObject.setShouldOverrideGlobalTimeFormat(5) // 24-Hour format with seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "HH:mm:ss")

        // Skip 6 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(7) // 12-hour with preceding zero and no seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm a")

        dataObject.setShouldOverrideGlobalTimeFormat(8) // 12-hour with preceding zero and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm:ss a")

        // Skip 9 since it's a placeholder
        dataObject.setShouldOverrideGlobalTimeFormat(10) // 12-hour without am/pm and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm")

        dataObject.setShouldOverrideGlobalTimeFormat(11) // 12-hour with preceding zero and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "hh:mm:ss")

        dataObject.setShouldOverrideGlobalTimeFormat(12) // 12-hour with preceding zero and seconds
        XCTAssertTrue(dataObject.timezoneFormat(DataStore.shared().timezoneFormat()) == "epoch")
    }

    func testSecondsDisplayForOverridenTimezone() {
        let dataObject = TimezoneData(with: california)
        UserDefaults.standard.set(NSNumber(value: 1), forKey: UserDefaultKeys.selectedTimeZoneFormatKey) // Set to 24-Hour Format

        // Test default behaviour
        let timezoneWithSecondsKeys = [4, 5, 8, 11]
        for timezoneKey in timezoneWithSecondsKeys {
            dataObject.setShouldOverrideGlobalTimeFormat(timezoneKey)
            XCTAssertTrue(dataObject.shouldShowSeconds(DataStore.shared().timezoneFormat()))
        }

        let timezoneWithoutSecondsKeys = [1, 2, 7, 10]
        for timezoneKey in timezoneWithoutSecondsKeys {
            dataObject.setShouldOverrideGlobalTimeFormat(timezoneKey)
            XCTAssertFalse(dataObject.shouldShowSeconds(DataStore.shared().timezoneFormat()))
        }

        // Test wrong override timezone key
        let wrongTimezoneKey = 88
        dataObject.setShouldOverrideGlobalTimeFormat(wrongTimezoneKey)
        XCTAssertFalse(dataObject.shouldShowSeconds(DataStore.shared().timezoneFormat()))

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
        XCTAssertTrue(dataObject.formattedTimezoneLabel() == "Ghar", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        dataObject.setLabel("")
        XCTAssertTrue(dataObject.formattedTimezoneLabel() == "Mumbai", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        dataObject.formattedAddress = nil
        XCTAssertTrue(dataObject.formattedTimezoneLabel() == "Asia", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        dataObject.setLabel("Jogeshwari")
        XCTAssertTrue(dataObject.formattedTimezoneLabel() == "Jogeshwari", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        // Unlikely scenario
        dataObject.setLabel("")
        dataObject.timezoneID = "GMT"
        XCTAssertTrue(dataObject.formattedTimezoneLabel() == "GMT", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")

        // Another unlikely scenario
        dataObject.setLabel("")
        dataObject.timezoneID = nil
        XCTAssertTrue(dataObject.formattedTimezoneLabel() == "Error", "Incorrect custom label returned by model \(dataObject.formattedTimezoneLabel())")
    }

    func testEquality() {
        let dataObject1 = TimezoneData(with: mumbai)
        let dataObject2 = TimezoneData(with: auckland)

        XCTAssertFalse(dataObject1 == dataObject2)
        XCTAssertFalse(dataObject1.isEqual(dataObject2))

        let dataObject3 = TimezoneData(with: mumbai)
        XCTAssertTrue(dataObject1 == dataObject3)
        XCTAssertTrue(dataObject1.isEqual(dataObject3))

        XCTAssertFalse(dataObject1.isEqual(nil))
    }

    func testWithAllLocales() {
        let dataObject1 = TimezoneData(with: mumbai)
        let operations = TimezoneDataOperations(with: dataObject1, store: DataStore.shared())

        for locale in Locale.availableIdentifiers {
            let currentLocale = Locale(identifier: locale)
            let localizedDate = operations.todaysDate(with: 0, locale: currentLocale)
            XCTAssertNotNil(localizedDate)
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
                                                                             format: dataObject.timezoneFormat(DataStore.shared().timezoneFormat()),
                                                                             timezoneIdentifier: dataObject.timezone(),
                                                                             locale: currentLocale)
            let convertedDate = dateFormatter.string(from: newDate)
            XCTAssertNotNil(convertedDate)
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
        XCTAssertEqual(subject.subviews.count, 2) // Two textfields
        XCTAssertEqual(subject.subviews.first?.layer?.animationKeys(), ["notimezone.emoji"])
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
        original.note = "Test note"

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
        XCTAssertEqual(restored?.note, original.note, "note should match")
        XCTAssertEqual(restored?.isSystemTimezone, original.isSystemTimezone, "isSystemTimezone should match")
        XCTAssertEqual(restored?.latitude, original.latitude, "latitude should match")
        XCTAssertEqual(restored?.longitude, original.longitude, "longitude should match")
    }
}
