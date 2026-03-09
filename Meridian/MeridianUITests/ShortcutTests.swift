// Copyright © 2015 Abhishek Banthia

import XCTest

class ShortcutTests: XCTestCase {
    var app: XCUIApplication!

    let randomIndex = Int(arc4random_uniform(26))

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tapMenubarIcon()

        if !app.tables["mainTableView"].exists {
            app.buttons["FloatingPin"].click()
            app.tapMenubarIcon()
        }
    }

    func testShortcuts() {
        app.tables["mainTableView"].typeKey(",", modifierFlags: .command)

        XCTAssertFalse(app.tables["mainTableView"].exists)

        let randomAlphabet = randomLetter()

        app.windows["Meridian"].otherElements["ShortcutControl"].click()
        app.windows["Meridian"].otherElements["ShortcutControl"].typeKey(randomAlphabet, modifierFlags: [.shift, .command])

        // Close the window to really test
        app.windows["Meridian"].buttons["_XCUI:CloseWindow"].click()

        app.typeKey(randomAlphabet, modifierFlags: [.shift, .command])
        XCTAssertTrue(app.tables["mainTableView"].exists)

        app.terminate()
        app.launch()

        app.typeKey(randomAlphabet, modifierFlags: [.shift, .command])
        XCTAssertTrue(app.tables["mainTableView"].exists)

        // Reset the shortcut
        app.tables["mainTableView"].typeKey(",", modifierFlags: .command)
        app.windows["Meridian"].otherElements["ShortcutControl"].click()
        app.windows["Meridian"].typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        app.windows["Meridian"].typeKey(randomAlphabet, modifierFlags: [.shift, .command])
        XCTAssertFalse(app.tables["mainTableView"].exists)
    }

    private func randomLetter() -> String {
        let alphabet: [String] = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        return alphabet[randomIndex]
    }
}
