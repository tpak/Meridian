// Copyright © 2026 Chris Tirpak

import XCTest

@testable import Meridian

/// Covers the v4 Cities "add" search after the rewrite that fixed the four reported bugs:
/// UTC not found, spaces breaking the query, common city names missing, and noisy ranking.
final class CitySearchServiceTests: XCTestCase {

    private func ids(_ query: String, excluding: Set<String> = []) -> [String] {
        CitySearchService.search(query, excluding: excluding).results.map { $0.timezoneID }
    }

    private func label(_ query: String, forZone tz: String) -> String? {
        CitySearchService.search(query, excluding: []).results.first { $0.timezoneID == tz }?.label
    }

    // Bug 1: searching "UTC" returned nothing because "UTC" isn't in knownTimeZoneIdentifiers.
    func testFindsUTC() {
        XCTAssertEqual(ids("utc").first, "UTC")
        XCTAssertTrue(ids("UTC").contains("UTC"), "search must be case-insensitive")
    }

    // Bug 2: any query with a space (e.g. "San Francisco") returned nothing.
    func testSpaceInQueryStillMatches() {
        XCTAssertTrue(ids("san fran").contains("America/Los_Angeles"))
        XCTAssertTrue(ids("san francisco").contains("America/Los_Angeles"))
        // A multi-word IANA name must also resolve via the spaced query.
        XCTAssertEqual(ids("new york").first, "America/New_York")
    }

    // Bug 3 + ranking: the obvious city must rank first, not be buried under same-zone neighbours.
    func testRanksExactCityFirst() {
        XCTAssertEqual(ids("new york").first, "America/New_York")
        XCTAssertEqual(ids("tokyo").first, "Asia/Tokyo")
        XCTAssertEqual(ids("london").first, "Europe/London")
        XCTAssertEqual(ids("denver").first, "America/Denver")
    }

    // Common city names that aren't IANA identifiers resolve to the correct zone via aliases.
    func testAliasCitiesResolveToCorrectZone() {
        XCTAssertTrue(ids("mumbai").contains("Asia/Calcutta"))
        XCTAssertTrue(ids("seattle").contains("America/Los_Angeles"))
        XCTAssertTrue(ids("boston").contains("America/New_York"))
    }

    // Aliases attach to one specific identifier, so "san fran" must NOT drag in other Pacific zones.
    func testAliasesDoNotSmearAcrossZone() {
        let results = ids("san fran")
        XCTAssertFalse(results.contains("America/Tijuana"))
        XCTAssertFalse(results.contains("America/Vancouver"))
    }

    func testExcludesInstalled() {
        XCTAssertFalse(ids("tokyo", excluding: ["Asia/Tokyo"]).contains("Asia/Tokyo"))
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(ids("").isEmpty)
        XCTAssertTrue(ids("   ").isEmpty)
    }

    // The strong-match flag gates the geocoder: a direct name hit suppresses it; an alias-only hit
    // (where the literal city name differs) lets it run to fetch precise coordinates.
    func testStrongMatchFlagGatesGeocoder() {
        XCTAssertTrue(CitySearchService.search("tokyo", excluding: []).hasStrongMatch)
        XCTAssertFalse(CitySearchService.search("mumbai", excluding: []).hasStrongMatch)
    }

    func testResultCountIsCapped() {
        XCTAssertLessThanOrEqual(ids("america").count, CitySearchService.maxResults)
    }

    // Consistency: an alias hit must be labelled with the city the user typed, not the zone's
    // default name — so adding "Bangalore" doesn't surprise the user with "Calcutta".
    func testAliasMatchLabelsWithSearchedCity() {
        XCTAssertEqual(label("bangalore", forZone: "Asia/Calcutta"), "Bangalore")
        XCTAssertEqual(label("pune", forZone: "Asia/Calcutta"), "Pune")
        XCTAssertEqual(label("seattle", forZone: "America/Los_Angeles"), "Seattle")
    }

    // A direct city-name hit keeps the zone's own city, not the (possibly partial) query.
    func testNameMatchKeepsZoneCityLabel() {
        XCTAssertEqual(label("san", forZone: "America/Argentina/San_Juan"), "San Juan")
        XCTAssertEqual(label("new york", forZone: "America/New_York"), "New York")
    }

    // Guards Issue C: "new y" is a strong prefix of New York, so it must NOT trigger a geocode
    // (which fuzzed into New Haven). hasStrongMatch == true is what suppresses the lookup.
    func testPartialOfKnownCityIsStrongMatch() {
        XCTAssertEqual(ids("new y").first, "America/New_York")
        XCTAssertTrue(CitySearchService.search("new y", excluding: []).hasStrongMatch)
    }
}
