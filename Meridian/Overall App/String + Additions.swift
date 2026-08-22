// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa

extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "Title for \(self)")
    }
}
