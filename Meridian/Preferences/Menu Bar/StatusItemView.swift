// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa

let compactModeTimeFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

/// v4 menu bar: render each favourite as a single line "● NAME TIME" with a per-city color dot.
/// The user can opt back into the legacy two-line (place over time) item via Settings → Menu Bar →
/// the "Stacked" preset (issue #142), which is what conserves horizontal width on small/notched
/// laptops with several favourites. Single-line stays the default — this is true unless the user
/// turns on the stacked layout, so the whole render pipeline branches on it at runtime.
var kMenubarV4SingleLine: Bool { !menubarStackedLayoutEnabled }

/// Whether the menu-bar item uses the legacy two-line stacked layout (city name over the time),
/// opt-in via Settings → Menu Bar → "Stacked" preset (issue #142). Default off → single-line.
/// Backed by the same raw-key convention as the sibling color-dots toggle; a write to it triggers
/// `UserDefaults.didChangeNotification`, which `StatusItemHandler` already observes to re-render
/// the menu-bar image in the new layout.
var menubarStackedLayoutEnabled: Bool {
    UserDefaults.standard.object(forKey: DaybreakDefaults.Keys.menubarStacked) as? Bool ?? false
}

/// Whether the leading color dot is shown (Settings → Menu Bar → Color dots; default on).
var menubarColorDotsEnabled: Bool {
    UserDefaults.standard.object(forKey: DaybreakDefaults.Keys.menubarColorDots) as? Bool ?? true
}

/// Menu-bar text color. Dynamic — resolves against the effective appearance active at draw
/// time — so the same drawing code renders correctly on every screen's menu bar, light or dark.
/// Do not bake a resolved white/black into rendered content: appearance-dependent content is
/// what fed the multi-display replicant CPU loop (#191).
let menubarTextColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
}
