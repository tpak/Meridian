// Copyright © 2015 Abhishek Banthia

@testable import CoreLoggerKit
import os
import XCTest

// MARK: - Logger Tests

final class LoggerTests: XCTestCase {

    // MARK: production(_:)

    func testProductionWithSimpleMessage() {
        Logger.production("Simple production message")
    }

    func testProductionWithEmptyMessage() {
        Logger.production("")
    }

    func testProductionWithSpecialCharacters() {
        Logger.production("Special chars: %@ %d %f \n\t\\")
    }

    func testProductionWithUnicode() {
        Logger.production("Unicode: \u{1F600}\u{1F680}\u{2603}")
    }

    // MARK: debug(_:)

    func testDebugWithSimpleMessage() {
        Logger.debug("Simple debug message")
    }

    func testDebugWithEmptyMessage() {
        Logger.debug("")
    }

    func testDebugRespectsEnabledFlag() {
        // When disabled (default), should not crash
        UserDefaults.standard.set(false, forKey: "com.tpak.meridian.debugLoggingEnabled")
        Logger.debug("Should be skipped")

        // When enabled, should not crash
        UserDefaults.standard.set(true, forKey: "com.tpak.meridian.debugLoggingEnabled")
        Logger.debug("Should be logged")

        // Reset
        UserDefaults.standard.removeObject(forKey: "com.tpak.meridian.debugLoggingEnabled")
    }

    func testDebugLoggingEnabledDefaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "com.tpak.meridian.debugLoggingEnabled")
        XCTAssertFalse(Logger.debugLoggingEnabled)
    }

    // MARK: Rapid successive calls

    func testRapidProductionCalls() {
        for i in 0..<50 {
            Logger.production("Rapid production message \(i)")
        }
    }

    func testRapidDebugCalls() {
        UserDefaults.standard.set(true, forKey: "com.tpak.meridian.debugLoggingEnabled")
        for i in 0..<50 {
            Logger.debug("Rapid debug message \(i)")
        }
        UserDefaults.standard.removeObject(forKey: "com.tpak.meridian.debugLoggingEnabled")
    }

    // MARK: exportLog

    func testExportLogToFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-meridian-log.txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Should not throw
        try Logger.exportLog(to: tempURL)

        // File should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
}

// MARK: - PerfLogger Tests

final class PerfLoggerTests: XCTestCase {

    func testStartMarker() {
        PerfLogger.startMarker("TestMarker")
    }

    func testEndMarker() {
        PerfLogger.endMarker("TestMarker")
    }

    func testMatchedStartAndEndMarkers() {
        PerfLogger.startMarker("MatchedMarker")
        PerfLogger.endMarker("MatchedMarker")
    }

    func testMultipleMarkerPairs() {
        for _ in 0..<10 {
            PerfLogger.startMarker("RepeatedMarker")
            PerfLogger.endMarker("RepeatedMarker")
        }
    }

    func testDisable() {
        PerfLogger.disable()
        // After disabling, signpost calls should still not crash
        PerfLogger.startMarker("AfterDisable")
        PerfLogger.endMarker("AfterDisable")
    }

    func testSignpostIDIsStable() {
        let id1 = PerfLogger.signpostID
        let id2 = PerfLogger.signpostID
        XCTAssertEqual(id1, id2)
    }

    func testPanelLogSubsystem() {
        // Verify the log object is valid (not nil) before disable
        let log = PerfLogger.panelLog
        XCTAssertNotNil(log)
    }

    // Reset panelLog after disable test to avoid affecting other tests
    override func tearDown() {
        // Re-enable by restoring the log (PerfLogger.panelLog is settable)
        PerfLogger.panelLog = OSLog(subsystem: "com.tpak.Meridian",
                                    category: "Open Panel")
        super.tearDown()
    }
}
