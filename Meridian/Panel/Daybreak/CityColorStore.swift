// Copyright © 2026 Chris Tirpak
//
// CityColorStore — per-city accent dot colors (README §G menu-bar dots + Settings → Cities color
// swatch). Stored additively as a [cityIdentity: hex] dictionary in UserDefaults so the persisted
// TimezoneData model is left untouched. Defaults are a stable, deterministic pick from the design's
// 8-swatch palette, so a city keeps the same color across launches until the user changes it.

import SwiftUI
import AppKit

enum CityColorStore {
    private static let key = "com.tpak.meridian.v4.cityColors"

    /// The design's per-city swatch palette (Settings → Cities).
    static let palette: [String] = [
        "#FF7A00", "#E8002D", "#00A19C", "#1E41FF", "#37BEDD", "#FF5FA2", "#7C8493", "#6366F1"
    ]

    static func hex(for identity: String) -> String {
        stored[identity] ?? defaultHex(for: identity)
    }

    static func setHex(_ hex: String, for identity: String) {
        var dict = stored
        dict[identity] = hex
        UserDefaults.standard.set(dict, forKey: key)
    }

    static func color(for identity: String) -> Color {
        Color(nsColor: nsColor(for: identity))
    }

    static func nsColor(for identity: String) -> NSColor {
        Self.nsColor(fromHex: hex(for: identity)) ?? .systemGray
    }

    // MARK: Internals

    private static var stored: [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func defaultHex(for identity: String) -> String {
        palette[stableIndex(identity, modulo: palette.count)]
    }

    /// Stable (process-independent) hash so default colors don't shuffle between launches.
    private static func stableIndex(_ string: String, modulo: Int) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return abs(hash) % max(1, modulo)
    }

    static func nsColor(fromHex hex: String) -> NSColor? {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = Int(string, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
