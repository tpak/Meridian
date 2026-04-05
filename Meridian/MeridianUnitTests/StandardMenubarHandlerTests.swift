// Copyright © 2015 Abhishek Banthia

import CoreModelKit
import XCTest

@testable import Meridian

class StandardMenubarHandlerTests: XCTestCase {
    private var mumbai: [String: Any] { TestTimezones.mumbai }

    private func makeMockStore(with menubarMode: Int = 1) -> DataStore {
        let defaults = UserDefaults(suiteName: "com.tpak.Meridian.StandardMenubarHandlerTests")!
        defaults.set(menubarMode, forKey: UserDefaultKeys.menubarCompactMode)
        XCTAssertNotEqual(defaults, UserDefaults.standard)
        return DataStore(with: defaults)
    }

    func testValidStandardMenubarHandler_returnMenubarTitle() {
        let store = makeMockStore()
        store.setTimezones(nil)

        // Save a menubar selected timezone
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        saveTimezoneToStore(dataObject, store: store)

        let menubarTimezones = store.menubarTimezones()
        XCTAssertTrue(menubarTimezones?.count == 1, "Count is \(String(describing: menubarTimezones?.count))")
    }

    func testUnfavouritedTimezone_returnEmptyMenubarTimezoneCount() {
        let store = makeMockStore()
        store.setTimezones(nil)

        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 0
        saveTimezoneToStore(dataObject, store: store)

        let menubarTimezones = store.menubarTimezones()
        XCTAssertTrue(menubarTimezones?.count == 0)
    }

    func testUnfavouritedTimezone_returnNilMenubarString() {
        let store = makeMockStore()
        store.setTimezones(nil)
        let menubarHandler = MenubarTitleProvider(with: store)
        let emptyMenubarString = menubarHandler.titleForMenubar()
        XCTAssertTrue(emptyMenubarString.isEmpty)

        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 0
        saveTimezoneToStore(dataObject, store: store)

        let menubarString = menubarHandler.titleForMenubar()
        XCTAssertTrue(menubarString.count == 0)
    }

    func testWithEmptyMenubarTimezones() {
        let store = makeMockStore()
        store.setTimezones(nil)
        let menubarHandler = MenubarTitleProvider(with: store)
        XCTAssertTrue(menubarHandler.titleForMenubar().isEmpty)
    }

    func testWithStandardMenubarMode() {
        let store = makeMockStore(with: 0)
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        saveTimezoneToStore(dataObject, store: store)

        let menubarHandler = MenubarTitleProvider(with: store)
        XCTAssertTrue(menubarHandler.titleForMenubar().isEmpty)
    }

    func testProviderPassingAllConditions() {
        let store = makeMockStore()
        let dataObject = TimezoneData(with: mumbai)
        dataObject.isFavourite = 1
        saveTimezoneToStore(dataObject, store: store)

        let menubarHandler = MenubarTitleProvider(with: store)
        XCTAssertFalse(menubarHandler.titleForMenubar().isEmpty)
    }
}
