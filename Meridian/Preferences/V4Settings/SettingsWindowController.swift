// Copyright © 2026 Chris Tirpak
//
// SettingsWindowController — hosts the SwiftUI Settings window (`SettingsRootView`). Opened from
// the Daybreak footer, the dock menu, and ⌘,.

import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 748, height: 744),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("MeridianV4Settings")
        window.setFrameAutosaveName("MeridianV4Settings")
        // Host via NSHostingController so the controller owns sizing/first-responder.
        window.contentViewController = NSHostingController(rootView: SettingsRootView())
        window.center()
        self.init(window: window)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
