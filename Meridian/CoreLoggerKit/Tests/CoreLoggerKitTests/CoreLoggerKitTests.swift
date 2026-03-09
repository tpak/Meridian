// Copyright © 2015 Abhishek Banthia

@testable import CoreLoggerKit
import os
import XCTest

// MARK: - Logger Tests

final class LoggerTests: XCTestCase {

    // MARK: log(object:for:)

    func testLogWithAnnotationsAndEvent() {
        let annotations: [String: Any] = ["key": "value", "count": 42]
        Logger.log(object: annotations, for: "TestEvent")
    }

    func testLogWithNilAnnotations() {
        Logger.log(object: nil, for: "TestEventNilAnnotations")
    }

    func testLogWithEmptyAnnotations() {
        Logger.log(object: [:], for: "TestEventEmptyAnnotations")
    }

    func testLogWithEmptyEventString() {
        Logger.log(object: ["key": "value"], for: "")
    }

    func testLogWithLargeAnnotations() {
        var annotations: [String: Any] = [:]
        for i in 0..<100 {
            annotations["key_\(i)"] = "value_\(i)"
        }
        Logger.log(object: annotations, for: "LargeAnnotationsEvent")
    }

    func testLogWithNestedAnnotations() {
        let annotations: [String: Any] = [
            "nested": ["inner": "value"],
            "array": [1, 2, 3],
            "bool": true,
            "nil_val": NSNull()
        ]
        Logger.log(object: annotations, for: "NestedEvent")
    }

    func testLogWithSpecialCharactersInEvent() {
        Logger.log(object: nil, for: "Event with spaces & special chars: %@ %d \n\t")
    }

    func testLogWithUnicodeEvent() {
        Logger.log(object: ["emoji": "test"], for: "Unicode: \u{1F600}\u{1F680}")
    }

    // MARK: info(_:)

    func testInfoWithSimpleMessage() {
        Logger.info("Simple info message")
    }

    func testInfoWithEmptyMessage() {
        Logger.info("")
    }

    func testInfoWithLongMessage() {
        let longMessage = String(repeating: "a", count: 10_000)
        Logger.info(longMessage)
    }

    func testInfoWithSpecialCharacters() {
        Logger.info("Special chars: %@ %d %f \n\t\\")
    }

    func testInfoWithUnicode() {
        Logger.info("Unicode: \u{1F600}\u{1F680}\u{2603}")
    }

    func testInfoWithNewlines() {
        Logger.info("Line 1\nLine 2\nLine 3")
    }

    // MARK: Rapid successive calls

    func testRapidLogCalls() {
        for i in 0..<50 {
            Logger.log(object: ["iteration": i], for: "RapidEvent" as NSString)
        }
    }

    func testRapidInfoCalls() {
        for i in 0..<50 {
            Logger.info("Rapid info message \(i)")
        }
    }

    // MARK: Logger instance

    func testLoggerIsNSObjectSubclass() {
        let logger = CoreLoggerKit.Logger()
        XCTAssertNotNil(logger)
        XCTAssertTrue(logger is NSObject)
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

    func testPerfLoggerIsNSObjectSubclass() {
        let perfLogger = PerfLogger()
        XCTAssertNotNil(perfLogger)
        XCTAssertTrue(perfLogger is NSObject)
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
