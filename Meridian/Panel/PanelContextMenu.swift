// Copyright © 2015 Abhishek Banthia

import Cocoa

/// Builds the "More Options" context menu for the panel.
/// Extracted from ParentPanelController to reduce god-class complexity.
enum PanelContextMenu {
    static func build(target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "More Options")

        let openPreferences = NSMenuItem(title: "Settings",
                                         action: #selector(ParentPanelController.openPreferencesWindow), keyEquivalent: "")
        let rateMeridian = NSMenuItem(title: "Support Meridian...",
                                      action: #selector(ParentPanelController.rate), keyEquivalent: "")
        let sendFeedback = NSMenuItem(title: "Send Feedback...",
                                      action: #selector(ParentPanelController.reportIssue), keyEquivalent: "")
        let terminateOption = NSMenuItem(title: "Quit Meridian",
                                         action: #selector(ParentPanelController.terminateClocker), keyEquivalent: "")

        let appDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "Meridian"
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "N/A"
        let longVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "N/A"
        let versionInfo = "\(appDisplayName) \(shortVersion) (\(longVersion))"
        let clockerVersionInfo = NSMenuItem(title: versionInfo, action: nil, keyEquivalent: "")
        clockerVersionInfo.isEnabled = false

        menu.addItem(openPreferences)
        menu.addItem(rateMeridian)
        menu.addItem(withTitle: "FAQs", action: #selector(ParentPanelController.openFAQs), keyEquivalent: "")
        menu.addItem(sendFeedback)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(clockerVersionInfo)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(terminateOption)

        return menu
    }
}
