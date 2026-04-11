// Copyright © 2015 Abhishek Banthia

import XCTest
@testable import Meridian

class TimeScrollerViewModelTests: XCTestCase {
    private var mockStore: MockDataStore!
    private var viewModel: TimeScrollerViewModel!

    override func setUp() {
        super.setUp()
        mockStore = MockDataStore()
        viewModel = TimeScrollerViewModel(dataStore: mockStore)
    }

    override func tearDown() {
        viewModel = nil
        mockStore = nil
        super.tearDown()
    }

    func testTotalSliderPointsWithDefaultRange() {
        // Default range is 6 days
        mockStore.preferences[UserDefaultKeys.futureSliderRange] = NSNumber(value: 6)
        let expectedPoints = (96 * 6 * 2) + 1
        XCTAssertEqual(viewModel.totalSliderPoints(), expectedPoints)
    }

    func testTotalSliderPointsWithCustomRange() {
        mockStore.preferences[UserDefaultKeys.futureSliderRange] = NSNumber(value: 1)
        let expectedPoints = (96 * 1 * 2) + 1
        XCTAssertEqual(viewModel.totalSliderPoints(), expectedPoints)
    }

    func testCalculateMinutesToAddAtCenter() {
        mockStore.preferences[UserDefaultKeys.futureSliderRange] = NSNumber(value: 1)
        let totalPoints = viewModel.totalSliderPoints()
        let centerIndex = totalPoints / 2
        
        let result = viewModel.calculateMinutesToAdd(for: centerIndex, baseDate: Date())
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, "Time Scroller")
    }

    func testCalculateMinutesToAddForward() {
        mockStore.preferences[UserDefaultKeys.futureSliderRange] = NSNumber(value: 1)
        let totalPoints = viewModel.totalSliderPoints()
        let centerIndex = totalPoints / 2
        let forwardIndex = centerIndex + 1

        // Use the same date for baseDate and now so minutes(from:) is deterministic.
        // forwardIndex == centerPoint + 1, so remainder = 0, minuteOffset = 0,
        // nextDate == baseDate, and nextDate.minutes(from: now) + 1 == 1.
        let fixedDate = Date()
        let result = viewModel.calculateMinutesToAdd(for: forwardIndex, baseDate: fixedDate, now: fixedDate)
        XCTAssertEqual(result.0, 1)
    }

    func testClosestQuarterTimeApproximation() {
        let date = viewModel.findClosestQuarterTimeApproximation()
        let calendar = Calendar.current
        let minutes = calendar.component(.minute, from: date)
        XCTAssertTrue([0, 15, 30, 45].contains(minutes))
    }
}
