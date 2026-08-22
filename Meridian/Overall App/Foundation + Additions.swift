// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLoggerKit

extension NSNotification.Name {
    static let customLabelChanged = NSNotification.Name("CLCustomLabelChangedNotification")
    static let interfaceStyleDidChange = NSNotification.Name("AppleInterfaceThemeChangedNotification")
}

extension NSImage.Name {
    // "Midnight Sundial" monochrome menu-bar glyph (Assets → MenuBarIcon, Render As: Template).
    // Shown when the user has no starred cities. Tinted by macOS; load with isTemplate = true.
    static let menubarIcon = NSImage.Name("MenuBarIcon")
}

extension NSView {
    func setAccessibility(_ identifier: String) {
        setAccessibilityIdentifier(identifier)
    }
}

extension NSKeyedArchiver {
    static func secureArchive(with object: Any) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
        } catch {
            Logger.production("secureArchive failed for \(type(of: object)): \(error)")
            return nil
        }
    }
}
