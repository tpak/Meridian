// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa

// MARK: - controlAccentColor swizzle + invalidation
//
// Why we swizzle:
// Without this, NSColor.controlAccentColor falls through to the
// `Accent Color` colorset in Media.xcassets — a baked-in Aston Martin
// green. So every NSPopUpButton selected indicator, NSSegmentedControl
// segment fill, NSCheckbox check, NSToolbarItem tab icon, and focus
// ring would stay green regardless of which team the user picks.
// We swap the class-method getter at app launch so AppKit's internal
// callers (and our own) get the live team color.
//
// Why a simple swizzle is not enough:
// controlAccentColor is implemented as an NSDynamicSystemColor — a
// dynamic system color whose resolution AppKit caches per
// NSAppearance. Even after the swizzle returns a new color value,
// AppKit reuses the previously-cached resolution for any surface that
// has already been drawn. NSToolbarItem also caches its tinted
// bitmap separately. Result: switching team A → team B in place does
// nothing visible until some other event (tab nav, window
// resize) forces a re-render.
//
// `NSApplication.mer_invalidateAccentEverywhere` posts the
// accentColorDidChange notification; observers (PanelController,
// AppearanceViewController preview) repaint the surfaces we
// explicitly tint with the team color.

enum AccentColorSwizzler {
    /// Idempotent — guarded with a static flag so repeated calls are no-ops.
    static func install() {
        struct Once { static var done = false }
        guard !Once.done else { return }
        Once.done = true

        // Swizzle +controlAccentColor only. This covers NSPopUpButton,
        // NSSegmentedControl, NSCheckbox, NSSlider, focus rings, etc.
        // The selected-tab pill background is left to read the asset
        // catalog (a neutral light gray) — chasing it through colorNamed:
        // and private _selectionMaterialTintColor swizzles wasn't reliably
        // working and the gray is unobtrusive enough that it doesn't fight
        // the team color elsewhere.
        let originalSel = #selector(getter: NSColor.controlAccentColor)
        let customSel = #selector(NSColor.mer_currentTeamAccentColor)
        guard let original = class_getClassMethod(NSColor.self, originalSel),
              let custom = class_getClassMethod(NSColor.self, customSel) else {
            return
        }
        method_exchangeImplementations(original, custom)
    }
}

extension NSColor {
    @objc class func mer_currentTeamAccentColor() -> NSColor {
        DataStore.shared().teamAccent.accentColor
    }
}

extension NSApplication {
    /// Lets observers (PanelController, OneWindowController) repaint
    /// the surfaces we explicitly tint with the team color: panel pin
    /// button, slider chevrons + reset button, Preferences toolbar
    /// icons (palette-baked SF Symbols).
    ///
    /// We do NOT attempt to invalidate AppKit's NSDynamicSystemColor
    /// caches here. Every approach we tried (window.appearance
    /// toggle, NSApp.deactivate/activate, tabStyle toggle, recursive
    /// setNeedsDisplay) had at least one failure mode. macOS doesn't
    /// expose a runtime API for changing controlAccentColor and
    /// expecting AppKit's cached renderings to follow. The reliable
    /// path is the one Apple takes for the system-wide accent change:
    /// quit and relaunch. AppearanceViewController offers that as a
    /// modal choice when the user picks a team.
    func mer_invalidateAccentEverywhere() {
        NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
    }
}

extension Notification.Name {
    /// Posted when the user changes the team accent in Appearance settings.
    /// PanelController observes this and triggers a redraw of the slider
    /// fill + pin button tint.
    static let accentColorDidChange = Notification.Name("com.tpak.meridian.accentColorDidChange")
}
