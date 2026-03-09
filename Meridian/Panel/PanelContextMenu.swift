// Copyright © 2015 Abhishek Banthia

import Cocoa

/// Builds the "More Options" context menu for the panel.
/// Extracted from ParentPanelController to reduce god-class complexity.
enum PanelContextMenu {
    static func build(target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "More Options")

        let openPreferences = NSMenuItem(title: "Settings",
                                         action: #selector(ParentPanelController.openPreferencesWindow), keyEquivalent: "")

        let terminateOption = NSMenuItem(title: "Quit Meridian",
                                         action: #selector(ParentPanelController.terminateMeridian), keyEquivalent: "")

        let appDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "Meridian"
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "N/A"
        let versionInfo = "\(appDisplayName) \(shortVersion)"
        let versionMenuItem = NSMenuItem(title: versionInfo, action: nil, keyEquivalent: "")
        versionMenuItem.isEnabled = false

        menu.addItem(openPreferences)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(versionMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(terminateOption)

        return menu
    }
}
