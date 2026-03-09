// Copyright © 2015 Abhishek Banthia

import XCTest

class CopyToClipboardTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testFullCopy() throws {
        app.tapMenubarIcon()

        let cell = app.tables["mainTableView"].cells.firstMatch
        let customLabel = cell.staticTexts["CustomNameLabelForCell"]
        guard let value = customLabel.value else { return }
        let time = cell.staticTexts["ActualTime"].value ?? "Nil Value"
        let expectedValue = "\(value) - \(time)"

        // Tap to copy!
        cell.click()

        let actualValue = NSPasteboard.general.string(forType: .string) ?? "Empty Pasteboard"
        XCTAssert(expectedValue == actualValue,
                  "Clipboard value (\(actualValue)) doesn't match expected result: \(expectedValue)")

        // Test full copy
        let cellCount = app.tables["mainTableView"].cells.count
        var clipboardValue: [String] = []
        for cellIndex in 0 ..< cellCount {
            let cell = app.tables["mainTableView"].cells.element(boundBy: cellIndex)
            let time = cell.staticTexts["ActualTime"].value ?? "Nil Value"
            clipboardValue.append("\(time)")
        }

        app.buttons["Share"].click()
    }

    func testModernSlider() {
        app.tapMenubarIcon()
        let modernSliderExists = app.collectionViews["ModernSlider"].exists
        app.tables["mainTableView"].typeKey(",", modifierFlags: .command)

        let appearanceTab = app.toolbars.buttons.element(boundBy: 1)
        appearanceTab.click()

        let miscTab = app.tabs.element(boundBy: 1)
        miscTab.click()

        if modernSliderExists {
            app.radioGroups["FutureSlider"].radioButtons["Hide"].click()
        } else {
            app.radioGroups["FutureSlider"].radioButtons["Show"].click()
        }

        app.tapMenubarIcon()

        let newFloatingSliderExists = app.collectionViews["ModernSlider"].exists
        XCTAssertNotEqual(newFloatingSliderExists, modernSliderExists)
    }
}
