// Copyright © 2015 Abhishek Banthia

import Cocoa
import Carbon.HIToolbox

final class GlobalShortcutMonitor {
    static let shared = GlobalShortcutMonitor()

    struct KeyCombo: Codable, Equatable {
        let keyCode: UInt16
        let modifierFlags: UInt  // NSEvent.ModifierFlags.rawValue

        var displayString: String {
            guard keyCode > 0 else {
                return "Click to Record Shortcut"
            }

            var modifierString = ""
            let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)

            if flags.contains(.control) {
                modifierString += "⌃"
            }
            if flags.contains(.option) {
                modifierString += "⌥"
            }
            if flags.contains(.shift) {
                modifierString += "⇧"
            }
            if flags.contains(.command) {
                modifierString += "⌘"
            }

            let keyString = keyCodeToString(keyCode)
            return modifierString + keyString
        }

        private static let keyCodeMap: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
            0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
            0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\",
            0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x72: "Help", 0x73: "Home", 0x74: "⇞", 0x75: "⌦", 0x77: "End", 0x79: "⇟",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
            0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
            0x67: "F11", 0x6F: "F12"
        ]

        private func keyCodeToString(_ keyCode: UInt16) -> String {
            Self.keyCodeMap[keyCode] ?? ""
        }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    var action: (() -> Void)?

    private let userDefaultsKey = "globalPing"
    private let legacyUserDefaultsKey = "values.globalPing"

    var currentShortcut: KeyCombo? {
        get {
            // First try to read from new format
            if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
               let keyCombo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                return keyCombo
            }

            // Try legacy format migration
            if let legacyDict = UserDefaults.standard.object(forKey: legacyUserDefaultsKey) as? [String: Any],
               let keyCode = legacyDict["keyCode"] as? NSNumber,
               let modifierFlags = legacyDict["modifierFlags"] as? NSNumber {
                let keyCombo = KeyCombo(keyCode: keyCode.uint16Value, modifierFlags: modifierFlags.uintValue)

                // Migrate to new format
                if let data = try? JSONEncoder().encode(keyCombo) {
                    UserDefaults.standard.set(data, forKey: userDefaultsKey)
                }

                return keyCombo
            }

            return nil
        }
        set {
            unregister()

            if let keyCombo = newValue {
                if let data = try? JSONEncoder().encode(keyCombo) {
                    UserDefaults.standard.set(data, forKey: userDefaultsKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }

            register()
        }
    }

    private init() {}

    func register() {
        unregister()

        guard let shortcut = currentShortcut, shortcut.keyCode > 0 else {
            return
        }

        let targetKeyCode = shortcut.keyCode
        let targetFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)

        // Global monitor (when app is not active)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetFlags {
                self?.action?()
            }
        }

        // Local monitor (when app IS active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetFlags {
                self?.action?()
                return nil  // Consume the event
            }
            return event
        }
    }

    func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
