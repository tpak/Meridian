// Copyright © 2015 Abhishek Banthia

import Cocoa

class ShortcutRecorderButton: NSButton {
    private var isRecording = false
    private var localMonitor: Any?
    var shortcutDidChange: ((GlobalShortcutMonitor.KeyCombo?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.isBordered = true
        self.bezelStyle = .rounded
        self.setButtonType(.momentaryPushIn)
        updateDisplay()
    }

    func updateDisplay() {
        let currentShortcut = GlobalShortcutMonitor.shared.currentShortcut
        if isRecording {
            self.title = "Type shortcut..."
            self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        } else if let shortcut = currentShortcut {
            self.title = shortcut.displayString
            self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        } else {
            self.title = "Click to Record Shortcut"
            self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        } else {
            super.mouseDown(with: event)
        }
    }

    private func startRecording() {
        isRecording = true
        updateDisplay()

        // Install local event monitor to capture keyDown events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .keyDown {
                return self.handleKeyDown(with: event)
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRecording = false
        updateDisplay()
    }

    private func handleKeyDown(with event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Handle Escape to clear shortcut
        if keyCode == 53 {  // Escape key
            stopRecording()
            shortcutDidChange?(nil)
            return nil
        }

        // Handle Delete/Backspace to clear shortcut
        if keyCode == 51 || keyCode == 117 {  // Delete or Forward Delete
            stopRecording()
            shortcutDidChange?(nil)
            return nil
        }

        // Require at least one modifier key (Command, Option, or Control)
        let hasValidModifier = modifierFlags.contains(.command) ||
                               modifierFlags.contains(.option) ||
                               modifierFlags.contains(.control)

        if !hasValidModifier {
            // Ignore plain keypresses without valid modifiers
            return nil
        }

        // Create and save the new shortcut
        let newShortcut = GlobalShortcutMonitor.KeyCombo(
            keyCode: keyCode,
            modifierFlags: modifierFlags.rawValue
        )

        stopRecording()
        shortcutDidChange?(newShortcut)
        return nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording {
            _ = handleKeyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
