// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Carbon.HIToolbox
import Cocoa
import CoreLoggerKit

extension Notification.Name {
    /// Posted whenever the global shortcut changes — recorded, cleared, or imported — so UI that
    /// mirrors it (the Settings recorder field) can refresh instead of showing a stale value.
    static let globalShortcutChanged = Notification.Name("com.tpak.meridian.globalShortcutChanged")
}

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

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerInstalled = false
    // 'MERD' — identifies our hot key in the shared Carbon event stream.
    private let hotKeyID = EventHotKeyID(signature: 0x4D45_5244, id: 1)
    var action: (() -> Void)?

    private let userDefaultsKey = "globalPing"
    private let legacyUserDefaultsKey = "values.globalPing"

    var currentShortcut: KeyCombo? {
        get {
            // First try to read from new format
            if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
                if let keyCombo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                    return keyCombo
                } else {
                    Logger.debug("GlobalShortcutMonitor: failed to decode stored shortcut, ignoring")
                }
            }

            // Try legacy format migration
            if let legacyDict = UserDefaults.standard.object(forKey: legacyUserDefaultsKey) as? [String: Any],
               let keyCode = legacyDict["keyCode"] as? NSNumber,
               let modifierFlags = legacyDict["modifierFlags"] as? NSNumber {
                let keyCombo = KeyCombo(keyCode: keyCode.uint16Value, modifierFlags: modifierFlags.uintValue)

                // Migrate to new format
                do {
                    let data = try JSONEncoder().encode(keyCombo)
                    UserDefaults.standard.set(data, forKey: userDefaultsKey)
                } catch {
                    Logger.production("GlobalShortcutMonitor: failed to encode shortcut during migration: \(error)")
                }

                return keyCombo
            }

            return nil
        }
        set {
            unregister()

            if let keyCombo = newValue {
                do {
                    let data = try JSONEncoder().encode(keyCombo)
                    UserDefaults.standard.set(data, forKey: userDefaultsKey)
                } catch {
                    Logger.production("GlobalShortcutMonitor: failed to encode shortcut: \(error)")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }

            register()
            NotificationCenter.default.post(name: .globalShortcutChanged, object: nil)
        }
    }

    private init() {}

    // Registers a real system-wide hot key via Carbon's RegisterEventHotKey.
    //
    // The previous implementation used NSEvent.addGlobalMonitorForEvents, which is a *passive*
    // observer: it needs Accessibility/Input-Monitoring permission to fire at all, and it can't
    // consume the event — so when another app was focused the keystroke still reached that app,
    // which beeped on the unhandled key equivalent (the "ding"). A Carbon hot key is delivered to
    // us system-wide, consumes the event (no ding), needs no special permission, and takes effect
    // immediately on register — so it also fixes the "didn't apply until relaunch" recording bug.
    func register() {
        unregister()

        guard let shortcut = currentShortcut, shortcut.keyCode > 0 else {
            return
        }

        installEventHandlerIfNeeded()

        let modifiers = Self.carbonModifiers(from: NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            Logger.production("GlobalShortcutMonitor: RegisterEventHotKey failed (status \(status)) — the combo may be taken by another app")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // Installs the kEventHotKeyPressed handler once for the lifetime of the (singleton) monitor.
    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }

            var firedID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &firedID)
            guard err == noErr else { return err }

            let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
            if firedID.signature == monitor.hotKeyID.signature && firedID.id == monitor.hotKeyID.id {
                DispatchQueue.main.async { monitor.action?() }
            }
            return noErr
        }, 1, &spec, selfPtr, nil)

        if status == noErr {
            eventHandlerInstalled = true
        } else {
            Logger.production("GlobalShortcutMonitor: InstallEventHandler failed (status \(status))")
        }
    }

    // Translates Cocoa modifier flags to the Carbon bitmask RegisterEventHotKey expects.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
