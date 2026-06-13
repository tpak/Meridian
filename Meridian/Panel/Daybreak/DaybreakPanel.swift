// Copyright © 2026 Chris Tirpak
//
// DaybreakPanel — the borderless NSPanel that hosts the v4 SwiftUI popover. Mirrors the legacy
// CustomPanel's key handling (⌘Q/⌘W/⌘,/⌘C, Esc) so the redesign keeps the same shortcuts, but is a
// fresh window so the original panel stays untouched.

import AppKit

final class DaybreakPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "q":
            NSApplication.shared.terminate(nil)
            return true
        case ",":
            (windowController as? DaybreakPanelController)?.openSettings()
            return true
        case "w":
            close()
            return true
        case "c":
            (windowController as? DaybreakPanelController)?.copyCurrentLocationToClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}
