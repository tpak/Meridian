// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

class MenubarTitleProvider {
    private let store: DataStoring

    init(with dataStore: DataStoring) {
        store = dataStore
    }

    func titleForMenubar() -> String {
        // If the menubar is in compact mode, we don't need any of the below calculations; exit early
        if store.shouldDisplay(.menubarCompactMode) {
            return ""
        }

        let menubarTimezones = store.menubarTimezoneObjects()
        if menubarTimezones.isEmpty == false {
            let titles = menubarTimezones.map { timezone -> String in
                let operationsObject = TimezoneDataOperations(with: timezone, store: store)
                return operationsObject.menuTitle().trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
            }

            return titles.joined(separator: " ")
        }

        return ""
    }
}
