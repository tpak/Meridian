// Copyright © 2015 Abhishek Banthia

import Cocoa

extension NSNotification.Name {
    static let customLabelChanged = NSNotification.Name("CLCustomLabelChangedNotification")
    static let interfaceStyleDidChange = NSNotification.Name("AppleInterfaceThemeChangedNotification")
}

extension NSPasteboard.PasteboardType {
    static let dragSession = NSPasteboard.PasteboardType(rawValue: "public.text")
}

extension NSNib.Name {
    static let panel = NSNib.Name("Panel")
}

extension NSImage.Name {
    static let menubarIcon = NSImage.Name("LightModeIcon")
}

extension NSView {
    func setAccessibility(_ identifier: String) {
        setAccessibilityIdentifier(identifier)
    }
}

extension NSKeyedArchiver {
    static func clocker_archive(with object: Any) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
    }
}
