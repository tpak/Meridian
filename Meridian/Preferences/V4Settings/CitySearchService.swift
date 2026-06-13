// Copyright © 2026 Chris Tirpak
//
// CitySearchService — instant, ranked local timezone/city search for the v4 Settings → Cities
// "add" field. Replaces the raw IANA-identifier substring match that missed UTC (not in
// knownTimeZoneIdentifiers), broke on spaces ("San Francisco"), and never surfaced common city
// names. It builds a one-time scored index of every known timezone plus a "UTC" entry and a small
// per-identifier alias map of famous cities, then ranks matches so the obvious result lands first
// (e.g. "new york" → America/New_York, not a pile of other Eastern-zone cities). Precise lookups
// for cities whose name isn't an IANA identifier (e.g. "San Francisco" → real coordinates) come
// from the async geocoder in CityListModel; this is the offline-capable, zero-latency first pass.

import Foundation

struct CitySearchResult: Identifiable, Equatable {
    enum Kind: Equatable { case timezone, city }

    let id: String
    let title: String        // primary line shown in the result row
    let timezoneID: String   // IANA identifier to install
    let label: String        // stored custom label (friendly city name / "UTC" / geocoded city)
    let kind: Kind
    let latitude: Double?
    let longitude: Double?

    /// A copy carrying a different stored label — used to relabel an alias hit with the city the
    /// user actually searched for (e.g. "Bangalore" instead of the zone's default "Calcutta").
    func relabeled(_ newLabel: String) -> CitySearchResult {
        CitySearchResult(id: id, title: title, timezoneID: timezoneID, label: newLabel,
                         kind: kind, latitude: latitude, longitude: longitude)
    }
}

enum CitySearchService {

    /// Outcome of a local search: ranked results plus whether the top hit was a strong, direct
    /// name match. `CityListModel` uses `hasStrongMatch` to decide whether the async geocoder is
    /// worth firing — skip it when the local index already nailed the city by name.
    struct LocalResult: Equatable {
        let results: [CitySearchResult]
        let hasStrongMatch: Bool
    }

    static let maxResults = 8
    /// A token-level (or better) match against the timezone's own city name. Below this threshold
    /// the only hit was via a parent region or an alias keyword, so a geocode is worthwhile.
    private static let strongScore = 700
    /// At or below this score the match came from an alias keyword, not the zone's own name.
    private static let aliasScoreCeiling = 400

    /// Ranked local results for `query`, omitting any timezone already in `installed`.
    static func search(_ query: String, excluding installed: Set<String>) -> LocalResult {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return LocalResult(results: [], hasStrongMatch: false) }

        var scored: [(score: Int, result: CitySearchResult)] = []
        for entry in index where !installed.contains(entry.result.timezoneID) {
            let value = score(entry, query: normalized, tokens: tokens)
            guard value > 0 else { continue }
            // An alias-tier hit means the user typed a city that ISN'T the zone's own name
            // (e.g. "bangalore" → Asia/Calcutta). Relabel it with the matched alias so installing it
            // is consistent with the geocoded path, instead of the zone's default city ("Calcutta").
            if value <= aliasScoreCeiling, let alias = bestAlias(entry.aliasList, query: normalized, tokens: tokens) {
                scored.append((value, entry.result.relabeled(alias)))
            } else {
                scored.append((value, entry.result))
            }
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score
                ? lhs.score > rhs.score
                : lhs.result.title.localizedStandardCompare(rhs.result.title) == .orderedAscending
        }

        let best = scored.first?.score ?? 0
        let results = scored.prefix(maxResults).map { $0.result }
        return LocalResult(results: Array(results), hasStrongMatch: best >= strongScore)
    }

    /// The alias keyword that the query matched, Title-Cased for use as a label ("san francisco" →
    /// "San Francisco"). Prefers a whole-query hit, then an all-tokens hit.
    private static func bestAlias(_ aliases: [String], query: String, tokens: [String]) -> String? {
        let match = aliases.first { $0.contains(query) }
            ?? aliases.first { alias in tokens.allSatisfy { alias.contains($0) } }
        return match?.capitalized
    }

    // MARK: - Scoring

    // Higher tiers are more direct matches, so the obvious answer ranks first. City-name matches
    // (the timezone's own last path component) always outrank parent-region and alias matches.
    private static func score(_ entry: IndexEntry, query: String, tokens: [String]) -> Int {
        if entry.cityName == query { return 1000 }
        if entry.cityName.hasPrefix(query) { return 900 }
        if entry.cityName.contains(query) { return 800 }
        if tokens.allSatisfy({ entry.cityName.contains($0) }) { return 700 }
        if entry.fullPath.contains(query) { return 600 }
        if tokens.allSatisfy({ entry.fullPath.contains($0) }) { return 500 }
        if !entry.aliases.isEmpty {
            if entry.aliases.contains(query) { return 400 }
            if tokens.allSatisfy({ entry.aliases.contains($0) }) { return 300 }
        }
        return 0
    }

    // MARK: - Index

    private struct IndexEntry {
        let result: CitySearchResult
        let cityName: String   // lowercased friendly last path component ("new york")
        let fullPath: String   // lowercased friendly full identifier ("america new york")
        let aliases: String    // lowercased space-joined alias keywords (for scoring)
        let aliasList: [String] // the same aliases, kept separate so a match can become a label
    }

    private static let index: [IndexEntry] = buildIndex()

    private static func buildIndex() -> [IndexEntry] {
        var entries: [IndexEntry] = []

        // "UTC" isn't in knownTimeZoneIdentifiers but IS a valid TimeZone identifier — add it
        // explicitly so the obvious search actually finds it.
        entries.append(IndexEntry(
            result: CitySearchResult(id: "UTC", title: "UTC", timezoneID: "UTC",
                                     label: "UTC", kind: .timezone, latitude: nil, longitude: nil),
            cityName: "utc",
            fullPath: "utc",
            aliases: "utc gmt universal coordinated zulu",
            aliasList: ["universal", "coordinated", "zulu"]
        ))

        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard TimeZone(identifier: identifier) != nil else { continue }
            let title = identifier.replacingOccurrences(of: "_", with: " ")
            let lastComponent = identifier.split(separator: "/").last.map(String.init) ?? identifier
            let label = lastComponent.replacingOccurrences(of: "_", with: " ")
            let cityName = label.lowercased()
            let fullPath = identifier
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .lowercased()

            let aliasList = aliasMap[identifier] ?? []
            entries.append(IndexEntry(
                result: CitySearchResult(id: identifier, title: title, timezoneID: identifier,
                                         label: label, kind: .timezone, latitude: nil, longitude: nil),
                cityName: cityName,
                fullPath: fullPath,
                aliases: aliasList.joined(separator: " "),
                aliasList: aliasList
            ))
        }
        return entries
    }

    /// Famous cities mapped to the IANA zone they actually observe. Unlike the legacy
    /// abbreviation-keyed tags, these attach to a single specific identifier, so "san fran" resolves
    /// to America/Los_Angeles only — not every Pacific-zone city. Each alias is genuinely correct
    /// (Seattle really does use America/Los_Angeles). The long tail is handled by the geocoder.
    private static let aliasMap: [String: [String]] = [
        "America/Los_Angeles": ["san francisco", "los angeles", "san diego", "san jose", "seattle",
                                "portland", "las vegas", "sacramento", "oakland", "silicon valley",
                                "bay area", "hollywood", "california", "sf", "la"],
        "America/New_York": ["new york", "nyc", "boston", "philadelphia", "miami", "atlanta",
                             "washington dc", "pittsburgh", "charlotte", "brooklyn", "manhattan"],
        "America/Chicago": ["chicago", "houston", "dallas", "austin", "san antonio", "memphis",
                            "new orleans", "milwaukee", "minneapolis", "kansas city"],
        "America/Denver": ["denver", "salt lake city", "albuquerque", "boulder", "santa fe"],
        "America/Phoenix": ["phoenix", "tucson", "arizona", "scottsdale", "mesa"],
        "America/Toronto": ["toronto", "ottawa", "montreal"],
        "America/Sao_Paulo": ["sao paulo", "rio de janeiro", "brasilia", "brazil"],
        "America/Mexico_City": ["mexico city", "guadalajara", "monterrey"],
        "Asia/Calcutta": ["mumbai", "delhi", "new delhi", "bangalore", "bengaluru", "hyderabad",
                          "chennai", "kolkata", "calcutta", "pune", "ahmedabad", "india"],
        "Asia/Kolkata": ["mumbai", "delhi", "new delhi", "bangalore", "bengaluru", "hyderabad",
                         "chennai", "kolkata", "calcutta", "pune", "ahmedabad", "india"],
        "Asia/Dubai": ["dubai", "abu dhabi", "uae"],
        "Asia/Shanghai": ["shanghai", "beijing", "shenzhen", "guangzhou", "china"],
        "Asia/Tokyo": ["tokyo", "osaka", "kyoto", "japan"],
        "Asia/Singapore": ["singapore"],
        "Europe/London": ["london", "manchester", "liverpool", "birmingham", "edinburgh", "glasgow"],
        "Europe/Paris": ["paris", "marseille", "lyon", "france"],
        "Europe/Berlin": ["berlin", "munich", "frankfurt", "hamburg", "cologne", "germany"],
        "Europe/Moscow": ["moscow", "saint petersburg"],
        "Australia/Sydney": ["sydney", "canberra"],
        "Australia/Melbourne": ["melbourne"],
        "Pacific/Honolulu": ["honolulu", "hawaii", "maui"]
    ]
}
