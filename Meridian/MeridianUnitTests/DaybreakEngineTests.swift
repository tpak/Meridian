// Copyright © 2026 Chris Tirpak
//
// Tests for the pure v4 Daybreak logic. These pin the Swift port to the design prototype's
// behavior (design_handoff_meridian_v4) and README §A–§F rules.

import XCTest
@testable import Meridian

final class DaybreakEngineTests: XCTestCase {

    // Example per-city sunrise/sunset (minutes since local midnight) from the prototype.
    private let melbourne = (sr: 444, ss: 1027)
    private let ist = (sr: 350, ss: 1126)
    private let utc = (sr: 427, ss: 1260)
    private let denver = (sr: 348, ss: 1228)

    private let minus = "\u{2212}"

    // MARK: - Phase (README §B)

    func testPhaseNightBeforeDawnWindow() {
        // lm well before sunrise → night.
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: 120, sunrise: denver.sr, sunset: denver.ss), .night)
    }

    func testPhaseNightAfterDuskWindow() {
        // lm at/after sunset + 50 → night.
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: denver.ss + 50, sunrise: denver.sr, sunset: denver.ss), .night)
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: 1400, sunrise: utc.sr, sunset: utc.ss), .night)
    }

    func testPhaseDawnWithinSunriseWindow() {
        // sr - 50 <= lm < sr + 50 → dawn.
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: denver.sr, sunrise: denver.sr, sunset: denver.ss), .dawn)
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: denver.sr - 49, sunrise: denver.sr, sunset: denver.ss), .dawn)
    }

    func testPhaseDayMidday() {
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: 720, sunrise: denver.sr, sunset: denver.ss), .day)
    }

    func testPhaseDuskWithinSunsetWindow() {
        // ss - 50 <= lm < ss + 50 → dusk.
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: denver.ss - 1, sunrise: denver.sr, sunset: denver.ss), .dusk)
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: denver.ss + 49, sunrise: denver.sr, sunset: denver.ss), .dusk)
    }

    func testPhaseBoundaryExactlyDawnStart() {
        // lm == sr - 50 is the first dawn minute (the night test uses strict <).
        XCTAssertEqual(DaybreakEngine.phase(localMinutes: denver.sr - 50, sunrise: denver.sr, sunset: denver.ss), .dawn)
    }

    func testIsNightGlyph() {
        XCTAssertTrue(DayPhase.night.isNight)
        XCTAssertFalse(DayPhase.day.isNight)
        XCTAssertFalse(DayPhase.dawn.isNight)
        XCTAssertFalse(DayPhase.dusk.isNight)
    }

    // MARK: - Next sun event (README §B)

    func testNextSunEventBeforeSunrise() {
        let e = DaybreakEngine.nextSunEvent(localMinutes: 100, sunrise: denver.sr, sunset: denver.ss)
        XCTAssertEqual(e, SunEvent(kind: .sunrise, minutes: denver.sr))
    }

    func testNextSunEventDuringDay() {
        let e = DaybreakEngine.nextSunEvent(localMinutes: 720, sunrise: denver.sr, sunset: denver.ss)
        XCTAssertEqual(e, SunEvent(kind: .sunset, minutes: denver.ss))
    }

    func testNextSunEventAfterSunsetWrapsToSunrise() {
        let e = DaybreakEngine.nextSunEvent(localMinutes: 1300, sunrise: denver.sr, sunset: denver.ss)
        XCTAssertEqual(e, SunEvent(kind: .sunrise, minutes: denver.sr))
    }

    // MARK: - Time formatting

    func testFormat12() {
        XCTAssertEqual(DaybreakEngine.format12(minutes: 1217).time, "8:17")
        XCTAssertEqual(DaybreakEngine.format12(minutes: 1217).period, "PM")
        XCTAssertEqual(DaybreakEngine.format12(minutes: 0).time, "12:00")
        XCTAssertEqual(DaybreakEngine.format12(minutes: 0).period, "AM")
        XCTAssertEqual(DaybreakEngine.format12(minutes: 720).time, "12:00")
        XCTAssertEqual(DaybreakEngine.format12(minutes: 720).period, "PM")
        XCTAssertEqual(DaybreakEngine.format12(minutes: 7 * 60 + 47).time, "7:47")
    }

    func testFormat24() {
        XCTAssertEqual(DaybreakEngine.format24(minutes: 1217), "20:17")
        XCTAssertEqual(DaybreakEngine.format24(minutes: 7 * 60 + 47), "07:47")
        XCTAssertEqual(DaybreakEngine.format24(minutes: 0), "00:00")
    }

    func testWrapMinutes() {
        XCTAssertEqual(DaybreakEngine.wrapMinutes(-30), 1410)
        XCTAssertEqual(DaybreakEngine.wrapMinutes(1500), 60)
        XCTAssertEqual(DaybreakEngine.wrapMinutes(720), 720)
    }

    // MARK: - Offsets (README §A)

    func testOffsetLabelHeroIsYourTime() {
        XCTAssertEqual(DaybreakEngine.offsetLabel(offsetMinutes: 0), "Your time")
    }

    func testOffsetLabelPositive() {
        // IST relative to Denver: 330 − (−360) = 690 → +11:30
        XCTAssertEqual(DaybreakEngine.offsetLabel(offsetMinutes: 690), "+11:30")
    }

    func testOffsetLabelNegativeUsesUnicodeMinus() {
        // IST relative to Melbourne: 330 − 600 = −270 → −4:30
        XCTAssertEqual(DaybreakEngine.offsetLabel(offsetMinutes: -270), "\(minus)4:30")
    }

    func testDayTag() {
        XCTAssertNil(DaybreakEngine.dayTag(dayDelta: 0))
        XCTAssertEqual(DaybreakEngine.dayTag(dayDelta: 1), "tmrw")
        XCTAssertEqual(DaybreakEngine.dayTag(dayDelta: 2), "+2d")
        XCTAssertEqual(DaybreakEngine.dayTag(dayDelta: -1), "yest.")
        XCTAssertEqual(DaybreakEngine.dayTag(dayDelta: -2), "2d ago")
    }

    // MARK: - Scrubber readout (README §F)

    func testDeltaLabel() {
        XCTAssertEqual(DaybreakEngine.deltaLabel(deltaMinutes: 0), "Now")
        XCTAssertEqual(DaybreakEngine.deltaLabel(deltaMinutes: 720), "+12:00")
        XCTAssertEqual(DaybreakEngine.deltaLabel(deltaMinutes: -90), "\(minus)1:30")
        XCTAssertEqual(DaybreakEngine.deltaLabel(deltaMinutes: 2880), "+2d")
        XCTAssertEqual(DaybreakEngine.deltaLabel(deltaMinutes: 2880 + 480), "+2d 8:00")
    }

    func testReadoutNow() {
        XCTAssertEqual(DaybreakEngine.readout(deltaMinutes: 0, currentLocalMinutes: 1217, weekdayShort: "Sun"),
                       "Now · 8:17 PM")
    }

    func testReadoutTraveling() {
        XCTAssertEqual(DaybreakEngine.readout(deltaMinutes: 2880, currentLocalMinutes: 1217, weekdayShort: "Wed"),
                       "+2d · Wed 8:17 PM")
    }

    // MARK: - Time parser (README §E)

    func testParse12HourWithSpace() {
        XCTAssertEqual(DaybreakEngine.parseTime("3:30 PM"), 15 * 60 + 30)
    }

    func testParse24Hour() {
        XCTAssertEqual(DaybreakEngine.parseTime("15:30"), 15 * 60 + 30)
    }

    func testParseCompactPM() {
        XCTAssertEqual(DaybreakEngine.parseTime("3pm"), 15 * 60)
    }

    func testParseHourOnly24() {
        XCTAssertEqual(DaybreakEngine.parseTime("3"), 3 * 60)
    }

    func testParseMidnightAndNoon() {
        XCTAssertEqual(DaybreakEngine.parseTime("12:00 AM"), 0)
        XCTAssertEqual(DaybreakEngine.parseTime("12 PM"), 12 * 60)
        XCTAssertEqual(DaybreakEngine.parseTime("12am"), 0)
    }

    func testParseDottedMeridiem() {
        XCTAssertEqual(DaybreakEngine.parseTime("7:47 a.m."), 7 * 60 + 47)
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(DaybreakEngine.parseTime("abc"))
        XCTAssertNil(DaybreakEngine.parseTime(""))
        XCTAssertNil(DaybreakEngine.parseTime("7:60"))      // minutes out of range
        XCTAssertNil(DaybreakEngine.parseTime("25"))        // 24h hour out of range
        XCTAssertNil(DaybreakEngine.parseTime("13:00 PM"))  // 12h hour out of range
        XCTAssertNil(DaybreakEngine.parseTime("0 AM"))      // 12h hour 0 invalid
    }

    // MARK: - Edited-time commit + clamp/snap (README §E/§F)

    func testOffsetForEditedTimeRecomputesDelta() {
        // City currently reads 480 (8:00); user types 9:00 (540) → delta moves +60.
        let d = DaybreakEngine.offsetForEditedTime(currentDelta: 0,
                                                   enteredMinutes: 540,
                                                   cityCurrentLocalMinutes: 480,
                                                   range: -2880...2880,
                                                   snapStep: 15)
        XCTAssertEqual(d, 60)
    }

    func testClampAndSnapRoundsTo15() {
        XCTAssertEqual(DaybreakEngine.clampAndSnap(67, range: -2880...2880, snapStep: 15), 60)
        XCTAssertEqual(DaybreakEngine.clampAndSnap(68, range: -2880...2880, snapStep: 15), 75)
    }

    func testClampAndSnapClampsToRange() {
        XCTAssertEqual(DaybreakEngine.clampAndSnap(9999, range: -2880...2880, snapStep: 15), 2880)
        XCTAssertEqual(DaybreakEngine.clampAndSnap(-9999, range: -2880...2880, snapStep: 15), -2880)
    }

    // MARK: - Sky ramp (README Design Tokens)

    func testSkyColorExactStops() {
        XCTAssertEqual(DaybreakEngine.skyColor(hour: 0).r, 27)
        XCTAssertEqual(DaybreakEngine.skyColor(hour: 0).g, 33)
        XCTAssertEqual(DaybreakEngine.skyColor(hour: 0).b, 56)

        XCTAssertEqual(DaybreakEngine.skyColor(hour: 12).r, 166)
        XCTAssertEqual(DaybreakEngine.skyColor(hour: 12).g, 196)
        XCTAssertEqual(DaybreakEngine.skyColor(hour: 12).b, 226)

        XCTAssertEqual(DaybreakEngine.skyColor(hour: 6).r, 44)
        XCTAssertEqual(DaybreakEngine.skyColor(hour: 18.2).r, 178)
    }

    func testSkyColorFlatRegion() {
        // Hours 0–5 are all the same night color.
        let a = DaybreakEngine.skyColor(hour: 2)
        XCTAssertEqual(a.r, 27); XCTAssertEqual(a.g, 33); XCTAssertEqual(a.b, 56)
    }

    func testSkyColorWraps() {
        // hour 25 → hour 1 → still in the flat night region.
        let w = DaybreakEngine.skyColor(hour: 25)
        XCTAssertEqual(w.r, 27); XCTAssertEqual(w.g, 33); XCTAssertEqual(w.b, 56)
    }
}
