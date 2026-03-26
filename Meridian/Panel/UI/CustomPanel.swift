// Copyright © 2015 Abhishek Banthia

import Cocoa

class CustomPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

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
            if let panelController = windowController as? ParentPanelController {
                panelController.openPreferencesWindow()
            }
            return true
        case "w":
            close()
            return true
        case "c":
            if let panelController = windowController as? ParentPanelController {
                panelController.copyFirstTimezoneToClipboard()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}
