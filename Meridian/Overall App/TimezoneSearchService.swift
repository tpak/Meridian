// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLoggerKit
import CoreModelKit

/// Shared timezone search logic used by PreferencesViewController.
enum TimezoneSearchService {
    /// Search local timezones matching the given query.
    static func searchLocalTimezones(_ query: String, in dataSource: SearchDataSource) {
        dataSource.searchTimezones(query.lowercased())
    }
}
