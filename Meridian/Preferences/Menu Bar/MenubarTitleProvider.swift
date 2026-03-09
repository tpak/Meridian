// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

class MenubarTitleProvider: NSObject {
    private let store: DataStoring

    init(with dataStore: DataStoring) {
        store = dataStore
        super.init()
    }

    func titleForMenubar() -> String? {
        guard let menubarTitles = store.menubarTimezones() else {
            return nil
        }

        // If the menubar is in compact mode, we don't need any of the below calculations; exit early
        if store.shouldDisplay(.menubarCompactMode) {
            return nil
        }

        if menubarTitles.isEmpty == false {
            let titles = menubarTitles.compactMap { data -> String? in
                guard let timezone = TimezoneData.customObject(from: data) else { return nil }
                let operationsObject = TimezoneDataOperations(with: timezone, store: store)
                return operationsObject.menuTitle().trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
            }

            return titles.joined(separator: " ")
        }

        return nil
    }
}
