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
        
        let baseDate = Date()
        let result = viewModel.calculateMinutesToAdd(for: forwardIndex, baseDate: baseDate)
        
        // forwardIndex is centerIndex + 1, so remainder is 0? 
        // Let's check logic: remainder = (index % (centerPoint + 1))
        // centerPoint = ceil(totalPoints / 2)
        // for totalPoints = 193, centerPoint = 97.
        // if index = 98 (centerPoint + 1), remainder = 98 % 98 = 0.
        // minuteOffset = 0 * 15 = 0.
        // nextDate = baseDate.
        // result.0 = nextDate.minutes(from: Date()) + 1 = 1.
        
        XCTAssertEqual(result.0, 1)
    }

    func testClosestQuarterTimeApproximation() {
        let date = viewModel.findClosestQuarterTimeApproximation()
        let calendar = Calendar.current
        let minutes = calendar.component(.minute, from: date)
        XCTAssertTrue([0, 15, 30, 45].contains(minutes))
    }
}
