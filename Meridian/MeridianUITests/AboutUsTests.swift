// Copyright © 2015 Abhishek Banthia

import XCTest

class AboutUsTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()

        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append(CLUITestingLaunchArgument)
        app.launch()

        app.tapMenubarIcon()
    }

    private func tapAboutTab() {
        let aboutTab = app.toolbars.buttons.element(boundBy: 4)
        aboutTab.click()
    }

    // The feedback window was removed along with Firebase.
    // The "Private Feedback" button now opens GitHub Issues in the browser.
    // We verify the button exists and is clickable; actual URL opening
    // cannot be validated in a UI test.
    func testPrivateFeedbackButtonExists() {
        app.tables["mainTableView"].typeKey(",", modifierFlags: .command)

        tapAboutTab()

        let privateFeedbackButton = app.buttons["ClockerPrivateFeedback"]
        XCTAssertTrue(privateFeedbackButton.exists, "Private Feedback button should exist on the About tab")
    }
}
