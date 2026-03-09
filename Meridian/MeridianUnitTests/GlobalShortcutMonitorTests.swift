// Copyright © 2015 Abhishek Banthia

import XCTest
@testable import Meridian

class GlobalShortcutMonitorTests: XCTestCase {
    let testUserDefaultsKey = "globalPing"

    override func setUp() {
        super.setUp()
        // Clear any stored shortcuts before each test
        UserDefaults.standard.removeObject(forKey: testUserDefaultsKey)
    }

    override func tearDown() {
        // Clean up after tests
        UserDefaults.standard.removeObject(forKey: testUserDefaultsKey)
        super.tearDown()
    }

    // MARK: - KeyCombo Display String Tests

    func testDisplayStringWithCommandModifier() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x01, // S
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertEqual(keyCombo.displayString, "⌘S")
    }

    func testDisplayStringWithMultipleModifiers() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x01, // S
            modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        )
        XCTAssertTrue(keyCombo.displayString.contains("⌘"))
        XCTAssertTrue(keyCombo.displayString.contains("⇧"))
        XCTAssertTrue(keyCombo.displayString.contains("S"))
    }

    func testDisplayStringWithAllModifiers() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x01, // S
            modifierFlags: NSEvent.ModifierFlags.control.rawValue |
                          NSEvent.ModifierFlags.option.rawValue |
                          NSEvent.ModifierFlags.shift.rawValue |
                          NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertTrue(keyCombo.displayString.contains("⌃"))
        XCTAssertTrue(keyCombo.displayString.contains("⌥"))
        XCTAssertTrue(keyCombo.displayString.contains("⇧"))
        XCTAssertTrue(keyCombo.displayString.contains("⌘"))
        XCTAssertTrue(keyCombo.displayString.contains("S"))
    }

    func testDisplayStringWithControlModifier() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x01, // S
            modifierFlags: NSEvent.ModifierFlags.control.rawValue
        )
        XCTAssertEqual(keyCombo.displayString, "⌃S")
    }

    func testDisplayStringWithOptionModifier() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x02, // D
            modifierFlags: NSEvent.ModifierFlags.option.rawValue
        )
        XCTAssertEqual(keyCombo.displayString, "⌥D")
    }

    func testDisplayStringWithShiftModifier() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x03, // F
            modifierFlags: NSEvent.ModifierFlags.shift.rawValue
        )
        XCTAssertEqual(keyCombo.displayString, "⇧F")
    }

    func testDisplayStringWithZeroKeyCode() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertEqual(keyCombo.displayString, "Click to Record Shortcut")
    }

    func testDisplayStringForCommonKeys() {
        // Test a few common key codes
        let keyCodes: [(UInt16, String)] = [
            (0x24, "↩"),    // Return
            (0x30, "⇥"),    // Tab
            (0x31, "Space"), // Space
            (0x33, "⌫"),    // Delete
            (0x35, "⎋"),    // Escape
            (0x7B, "←"),    // Left Arrow
            (0x7C, "→"),    // Right Arrow
            (0x7D, "↓"),    // Down Arrow
            (0x7E, "↑")     // Up Arrow
        ]

        for (keyCode, expectedKey) in keyCodes {
            let keyCombo = GlobalShortcutMonitor.KeyCombo(
                keyCode: keyCode,
                modifierFlags: 0
            )
            XCTAssertEqual(keyCombo.displayString, expectedKey,
                          "Key code \(keyCode) should display as \(expectedKey)")
        }
    }

    func testDisplayStringForFunctionKeys() {
        let keyCodes: [(UInt16, String)] = [
            (0x7A, "F1"),
            (0x78, "F2"),
            (0x63, "F3"),
            (0x76, "F4"),
            (0x60, "F5")
        ]

        for (keyCode, expectedKey) in keyCodes {
            let keyCombo = GlobalShortcutMonitor.KeyCombo(
                keyCode: keyCode,
                modifierFlags: 0
            )
            XCTAssertEqual(keyCombo.displayString, expectedKey,
                          "Key code \(keyCode) should display as \(expectedKey)")
        }
    }

    // MARK: - Shortcut Storage Tests

    func testSettingShortcutStoresInUserDefaults() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let monitor = GlobalShortcutMonitor.shared
        monitor.currentShortcut = keyCombo

        let storedData = UserDefaults.standard.data(forKey: testUserDefaultsKey)
        XCTAssertNotNil(storedData)

        let decodedCombo = try? JSONDecoder().decode(GlobalShortcutMonitor.KeyCombo.self, from: storedData!)
        XCTAssertNotNil(decodedCombo)
        XCTAssertEqual(decodedCombo?.keyCode, keyCombo.keyCode)
        XCTAssertEqual(decodedCombo?.modifierFlags, keyCombo.modifierFlags)
    }

    func testRetrievingShortcutFromUserDefaults() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let data = try! JSONEncoder().encode(keyCombo)
        UserDefaults.standard.set(data, forKey: testUserDefaultsKey)

        let monitor = GlobalShortcutMonitor.shared
        let retrievedCombo = monitor.currentShortcut

        XCTAssertNotNil(retrievedCombo)
        XCTAssertEqual(retrievedCombo?.keyCode, keyCombo.keyCode)
        XCTAssertEqual(retrievedCombo?.modifierFlags, keyCombo.modifierFlags)
    }

    func testSettingShortcutToNilClearsIt() {
        // First, set a shortcut
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let monitor = GlobalShortcutMonitor.shared
        monitor.currentShortcut = keyCombo

        XCTAssertNotNil(UserDefaults.standard.data(forKey: testUserDefaultsKey))

        // Now clear it
        monitor.currentShortcut = nil

        XCTAssertNil(UserDefaults.standard.data(forKey: testUserDefaultsKey))
        XCTAssertNil(monitor.currentShortcut)
    }

    // MARK: - KeyCombo Equality Tests

    func testKeyComboEquality() {
        let keyCombo1 = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let keyCombo2 = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        XCTAssertEqual(keyCombo1, keyCombo2)
    }

    func testKeyComboInequality() {
        let keyCombo1 = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let keyCombo2 = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x01,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        XCTAssertNotEqual(keyCombo1, keyCombo2)
    }

    func testKeyComboInequalityWithDifferentModifiers() {
        let keyCombo1 = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let keyCombo2 = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.shift.rawValue
        )

        XCTAssertNotEqual(keyCombo1, keyCombo2)
    }

    // MARK: - KeyCombo Codable Tests

    func testKeyComboEncoding() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let encoder = JSONEncoder()
        let data = try? encoder.encode(keyCombo)

        XCTAssertNotNil(data)
    }

    func testKeyComboDecoding() {
        let keyCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue
        )

        let encoder = JSONEncoder()
        let data = try! encoder.encode(keyCombo)

        let decoder = JSONDecoder()
        let decodedCombo = try? decoder.decode(GlobalShortcutMonitor.KeyCombo.self, from: data)

        XCTAssertNotNil(decodedCombo)
        XCTAssertEqual(decodedCombo?.keyCode, keyCombo.keyCode)
        XCTAssertEqual(decodedCombo?.modifierFlags, keyCombo.modifierFlags)
    }

    func testKeyComboRoundTrip() {
        let originalCombo = GlobalShortcutMonitor.KeyCombo(
            keyCode: 0x00,
            modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
        )

        let data = try! JSONEncoder().encode(originalCombo)
        let decodedCombo = try! JSONDecoder().decode(GlobalShortcutMonitor.KeyCombo.self, from: data)

        XCTAssertEqual(originalCombo, decodedCombo)
    }
}
