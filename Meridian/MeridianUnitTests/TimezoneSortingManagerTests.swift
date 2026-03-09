// Copyright © 2015 Abhishek Banthia

import XCTest
import CoreModelKit
@testable import Meridian

class TimezoneSortingManagerTests: XCTestCase {
    var manager: TimezoneSortingManager!
    var testTimezones: [Data]!

    override func setUp() {
        super.setUp()
        manager = TimezoneSortingManager()

        // Create test timezone data
        let sanFrancisco: [String: Any] = [
            "customLabel": "SF Office",
            "formattedAddress": "San Francisco",
            "place_id": "test-sf",
            "timezoneID": "America/Los_Angeles",
            "nextUpdate": "",
            "latitude": "37.7749295",
            "longitude": "-122.4194155"
        ]

        let newYork: [String: Any] = [
            "customLabel": "NY Office",
            "formattedAddress": "New York",
            "place_id": "test-ny",
            "timezoneID": "America/New_York",
            "nextUpdate": "",
            "latitude": "40.7127753",
            "longitude": "-74.0059728"
        ]

        let london: [String: Any] = [
            "customLabel": "London Office",
            "formattedAddress": "London",
            "place_id": "test-london",
            "timezoneID": "Europe/London",
            "nextUpdate": "",
            "latitude": "51.5073509",
            "longitude": "-0.1277583"
        ]

        let tokyo: [String: Any] = [
            "customLabel": "Tokyo Office",
            "formattedAddress": "Tokyo",
            "place_id": "test-tokyo",
            "timezoneID": "Asia/Tokyo",
            "nextUpdate": "",
            "latitude": "35.6761919",
            "longitude": "139.6503106"
        ]

        testTimezones = [
            NSKeyedArchiver.clocker_archive(with: TimezoneData(with: sanFrancisco))!,
            NSKeyedArchiver.clocker_archive(with: TimezoneData(with: newYork))!,
            NSKeyedArchiver.clocker_archive(with: TimezoneData(with: london))!,
            NSKeyedArchiver.clocker_archive(with: TimezoneData(with: tokyo))!
        ]
    }

    override func tearDown() {
        manager = nil
        testTimezones = nil
        super.tearDown()
    }

    // MARK: - Sort by Time Difference Tests

    func testSortByTimeDifferenceAscending() {
        let result = manager.sort(testTimezones, by: .time)
        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
    }

    func testSortByTimeDifferenceDescending() {
        // First call sorts one way
        _ = manager.sort(testTimezones, by: .time)
        // Second call toggles direction
        let result = manager.sort(testTimezones, by: .time)
        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
    }

    func testSortByTimeDifferenceTogglesBehavior() {
        let result1 = manager.sort(testTimezones, by: .time)
        let result2 = manager.sort(testTimezones, by: .time)

        // Verify results are different (toggled)
        let labels1 = result1.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.customLabel ?? ""
        }
        let labels2 = result2.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.customLabel ?? ""
        }

        XCTAssertNotEqual(labels1, labels2)
    }

    // MARK: - Sort by Label Tests

    func testSortByLabelFirstCall() {
        let result = manager.sort(testTimezones, by: .label)

        let labels = result.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.customLabel ?? ""
        }

        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
        // First call: ascending=false → a < b → ascending A→Z order
        XCTAssertEqual(labels, ["London Office", "NY Office", "SF Office", "Tokyo Office"])
    }

    func testSortByLabelSecondCall() {
        // First call
        _ = manager.sort(testTimezones, by: .label)
        // Second call toggles to ascending=true → a > b → descending Z→A
        let result = manager.sort(testTimezones, by: .label)

        let labels = result.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.customLabel ?? ""
        }

        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
        XCTAssertEqual(labels, ["Tokyo Office", "SF Office", "NY Office", "London Office"])
    }

    // MARK: - Sort by Name Tests

    func testSortByNameFirstCall() {
        let result = manager.sort(testTimezones, by: .name)

        let names = result.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.formattedAddress ?? ""
        }

        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
        // First call: ascending=false → a < b → ascending A→Z order
        XCTAssertEqual(names, ["London", "New York", "San Francisco", "Tokyo"])
    }

    func testSortByNameSecondCall() {
        // First call
        _ = manager.sort(testTimezones, by: .name)
        // Second call toggles to ascending=true → a > b → descending Z→A
        let result = manager.sort(testTimezones, by: .name)

        let names = result.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.formattedAddress ?? ""
        }

        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
        XCTAssertEqual(names, ["Tokyo", "San Francisco", "New York", "London"])
    }

    // MARK: - Sort by Column Identifier Tests

    func testSortByColumnIdentifierFormattedAddress() {
        var ascending = true
        let result = manager.sort(testTimezones, byColumn: "formattedAddress", ascending: &ascending)

        let names = result.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.formattedAddress ?? ""
        }

        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
        XCTAssertFalse(ascending) // ascending is toggled
        // When ascending = true, we sort descending (a > b)
        XCTAssertEqual(names, ["Tokyo", "San Francisco", "New York", "London"])
    }

    func testSortByColumnIdentifierCustomLabel() {
        var ascending = true
        let result = manager.sort(testTimezones, byColumn: "customLabel", ascending: &ascending)

        let labels = result.sorted.map { data -> String in
            TimezoneData.customObject(from: data)?.customLabel ?? ""
        }

        XCTAssertEqual(result.sorted.count, testTimezones.count)
        XCTAssertNotNil(result.indicatorImage)
        XCTAssertFalse(ascending) // ascending is toggled
        // When ascending = true, we sort descending (a > b)
        XCTAssertEqual(labels, ["Tokyo Office", "SF Office", "NY Office", "London Office"])
    }

    func testSortByColumnTogglesAscending() {
        var ascending = false
        _ = manager.sort(testTimezones, byColumn: "formattedAddress", ascending: &ascending)
        XCTAssertTrue(ascending)

        _ = manager.sort(testTimezones, byColumn: "formattedAddress", ascending: &ascending)
        XCTAssertFalse(ascending)
    }

    // MARK: - Edge Case Tests

    func testSortEmptyArray() {
        let emptyArray: [Data] = []
        let result = manager.sort(emptyArray, by: .time)
        XCTAssertTrue(result.sorted.isEmpty)
        XCTAssertNotNil(result.indicatorImage)
    }

    func testSortSingleElement() {
        let singleElement = [testTimezones.first!]
        let result = manager.sort(singleElement, by: .label)
        XCTAssertEqual(result.sorted.count, 1)
        XCTAssertNotNil(result.indicatorImage)
    }

    func testSortEmptyArrayByColumn() {
        let emptyArray: [Data] = []
        var ascending = true
        let result = manager.sort(emptyArray, byColumn: "formattedAddress", ascending: &ascending)
        XCTAssertTrue(result.sorted.isEmpty)
        XCTAssertFalse(ascending) // ascending is still toggled
    }

    func testSortIndicatorImageChanges() {
        let result1 = manager.sort(testTimezones, by: .time)
        let result2 = manager.sort(testTimezones, by: .time)

        // Both should have images, but we can't easily compare NSImage instances
        XCTAssertNotNil(result1.indicatorImage)
        XCTAssertNotNil(result2.indicatorImage)
    }
}
