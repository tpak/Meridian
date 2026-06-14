// Copyright © 2026 Chris Tirpak
//
// DaybreakTokens — SwiftUI design tokens for the v4 "Daybreak" popover.
//
// Values are transcribed verbatim from the design handoff
// (`design_handoff_meridian_v4` — "Design Tokens" section + Dynamic behavior §C/§D).
// There is no pre-existing token/Themer system in the app, so this is the single source of
// truth for Daybreak surface colors, hero sky gradients, sun/moon discs, and row tints.
//
// Light/dark are resolved from the SwiftUI `colorScheme` (the design's Dark/Light toggle is a
// prototype-only affordance; the real app follows macOS, honoring the user's Theme preference).
// The warm scrubber/handle accent is a fixed gold per the spec — the user-selectable TeamAccent
// livery is reserved for the Settings window.

import SwiftUI
import AppKit

/// Precise font weights + tabular digits matching the design's CSS weights (e.g. 640, 580), which
/// don't map onto SwiftUI's named `Font.Weight` cases. Bridges through `NSFont` so we also get true
/// monospaced (tabular) digits for the times.
enum DaybreakFont {
    /// Map a CSS font-weight (100–900) to an `NSFont.Weight` by interpolating standard anchors.
    static func nsWeight(_ css: Double) -> NSFont.Weight {
        let anchors: [(css: Double, w: CGFloat)] = [
            (100, -0.8), (200, -0.6), (300, -0.4), (400, 0), (500, 0.23),
            (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62)
        ]
        if css <= anchors.first!.css { return NSFont.Weight(anchors.first!.w) }
        if css >= anchors.last!.css { return NSFont.Weight(anchors.last!.w) }
        for i in 0..<(anchors.count - 1) {
            let lo = anchors[i], hi = anchors[i + 1]
            if css >= lo.css && css <= hi.css {
                let f = CGFloat((css - lo.css) / (hi.css - lo.css))
                return NSFont.Weight(lo.w + (hi.w - lo.w) * f)
            }
        }
        return .regular
    }

    /// Tabular-figure font at an exact CSS weight (for times).
    static func digit(_ size: CGFloat, _ css: Double) -> Font {
        Font(NSFont.monospacedDigitSystemFont(ofSize: size, weight: nsWeight(css)))
    }

    /// Proportional system font at an exact CSS weight (for names/labels).
    static func text(_ size: CGFloat, _ css: Double) -> Font {
        Font(NSFont.systemFont(ofSize: size, weight: nsWeight(css)))
    }
}

/// 0–255 RGB(A) → SwiftUI sRGB Color. Local helper to avoid colliding with any app-wide hex init.
private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
    Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
}

/// Surface/structural colors for the popover, resolved per appearance.
struct DaybreakPalette {
    let isDark: Bool
    let canvas: Color          // behind the popover
    let surface: Color         // popover body
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let hairline: Color        // borders / dividers
    let tick: Color            // scrubber hour ticks
    let dayTick: Color         // scrubber day-boundary markers
    let foot: Color            // footer links
    let footVersion: Color     // footer version label
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    static let dark = DaybreakPalette(
        isDark: true,
        canvas: rgb(14, 15, 19),
        surface: rgb(23, 25, 34),
        text: rgb(241, 241, 245),
        textSecondary: rgb(235, 235, 245, 0.55),
        textTertiary: rgb(235, 235, 245, 0.40),
        hairline: rgb(255, 255, 255, 0.08),
        tick: rgb(255, 255, 255, 0.22),
        dayTick: rgb(255, 255, 255, 0.50),
        foot: rgb(235, 235, 245, 0.50),
        footVersion: rgb(235, 235, 245, 0.30),
        shadowColor: rgb(0, 0, 0, 0.55), shadowRadius: 35, shadowY: 28
    )

    static let light = DaybreakPalette(
        isDark: false,
        canvas: rgb(233, 234, 238),
        surface: rgb(251, 251, 253),
        text: rgb(26, 27, 32),
        textSecondary: rgb(60, 60, 67, 0.60),
        textTertiary: rgb(60, 60, 67, 0.45),
        hairline: rgb(0, 0, 0, 0.07),
        tick: rgb(0, 0, 0, 0.18),
        dayTick: rgb(0, 0, 0, 0.42),
        foot: rgb(60, 60, 67, 0.55),
        footVersion: rgb(60, 60, 67, 0.32),
        shadowColor: rgb(0, 0, 0, 0.18), shadowRadius: 35, shadowY: 28
    )

    static func resolve(_ scheme: ColorScheme) -> DaybreakPalette {
        scheme == .dark ? .dark : .light
    }

    /// Warm gold accent for the Daybreak scrubber (README tokens: `#ffc24d` dark / `#c98a2a` light).
    var accent: Color { isDark ? rgb(255, 194, 77) : rgb(201, 138, 42) }

    /// Text color drawn on top of the accent-filled readout pill when traveling.
    var onAccent: Color { isDark ? rgb(26, 19, 0) : rgb(58, 38, 0) }

    /// Readout pill background when NOT traveling.
    var readoutIdleBackground: Color { isDark ? rgb(255, 255, 255, 0.07) : rgb(0, 0, 0, 0.05) }

    /// Small round chevron button background.
    var chevronButtonBackground: Color { isDark ? rgb(255, 255, 255, 0.05) : rgb(0, 0, 0, 0.03) }

    /// Inline time-edit field background/border (city rows).
    var editFieldBackground: Color { isDark ? rgb(255, 255, 255, 0.10) : rgb(0, 0, 0, 0.05) }
    var editFieldBorder: Color { isDark ? rgb(255, 255, 255, 0.30) : rgb(0, 0, 0, 0.20) }
}

/// Hero sky gradient + notch color, keyed by the current location's phase (README §C).
enum DaybreakSky {
    /// 135° gradient ≈ top-leading → bottom-trailing.
    static func gradient(for phase: DayPhase) -> LinearGradient {
        LinearGradient(colors: stops(for: phase), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func stops(for phase: DayPhase) -> [Color] {
        switch phase {
        case .night: return [rgb(16, 18, 43), rgb(42, 47, 94)]    // #10122b → #2a2f5e
        case .dawn:  return [rgb(70, 64, 111), rgb(255, 158, 109)] // #46406f → #ff9e6d
        case .day:   return [rgb(52, 80, 127), rgb(111, 147, 196)] // #34507f → #6f93c4
        case .dusk:  return [rgb(58, 47, 94), rgb(255, 122, 89)]   // #3a2f5e → #ff7a59
        }
    }

    /// The notch (small triangle pointing at the menu-bar item) matches the gradient's top color.
    static func notchColor(for phase: DayPhase) -> Color {
        switch phase {
        case .night: return rgb(16, 18, 43)
        case .dawn:  return rgb(70, 64, 111)
        case .day:   return rgb(52, 80, 127)
        case .dusk:  return rgb(58, 47, 94)
        }
    }
}

/// Sun/moon disc gradients + glows (README "Sun / Moon discs"). The glyph is a moon only when the
/// phase is night; otherwise a sun (README §B).
enum SunMoonStyle {
    /// Radial gradient for the disc. `center` matches the prototype's off-center highlight.
    static func gradient(isNight: Bool, diameter: CGFloat) -> RadialGradient {
        let colors: [Color] = isNight
            ? [rgb(223, 225, 248), rgb(139, 144, 232)]   // moon: #dfe1f8 → #8b90e8
            : [rgb(242, 207, 134), rgb(221, 158, 48)]    // sun:  #f2cf86 → #dd9e30
        let center: UnitPoint = isNight ? UnitPoint(x: 0.38, y: 0.38) : UnitPoint(x: 0.42, y: 0.38)
        return RadialGradient(colors: colors, center: center, startRadius: 0, endRadius: diameter * 0.62)
    }

    /// Glow color + blur radius for the disc's drop shadow, scaled by where it appears.
    enum Context { case row, hero, handle }

    static func glow(isNight: Bool, context: Context, isDark: Bool) -> (color: Color, radius: CGFloat) {
        switch context {
        case .row:
            return isNight
                ? (rgb(139, 144, 232, isDark ? 0.55 : 0.40), isDark ? 9 : 8)
                : (rgb(216, 158, 48, isDark ? 0.30 : 0.26), isDark ? 7 : 6)
        case .hero:
            return isNight
                ? (rgb(139, 144, 232, isDark ? 0.65 : 0.50), isDark ? 18 : 16)
                : (isDark ? rgb(216, 158, 48, 0.42) : rgb(220, 168, 64, 0.42), isDark ? 13 : 12)
        case .handle:
            return isNight
                ? (rgb(139, 144, 232, 0.70), 9)
                : (rgb(224, 170, 80, 0.60), 8)
        }
    }
}

/// City-row tint (README §D): a subtle phase-keyed gradient overlay + border. Warm for
/// day/dawn/dusk, indigo for night.
enum DaybreakTints {
    /// (gradient start, gradient end, border) per phase + appearance.
    static func card(for phase: DayPhase, isDark: Bool) -> (gradient: LinearGradient, border: Color) {
        let stops = tint(for: phase, isDark: isDark)
        let grad = LinearGradient(colors: [stops.0, stops.1], startPoint: .topLeading, endPoint: .bottomTrailing)
        return (grad, stops.2)
    }

    private static func tint(for phase: DayPhase, isDark: Bool) -> (Color, Color, Color) {
        if isDark {
            switch phase {
            case .day:   return (rgb(255, 190, 90, 0.16), rgb(255, 150, 70, 0.07), rgb(255, 190, 90, 0.16))
            case .dawn:  return (rgb(255, 150, 110, 0.20), rgb(255, 110, 90, 0.10), rgb(255, 150, 110, 0.22))
            case .dusk:  return (rgb(255, 120, 90, 0.20), rgb(255, 90, 70, 0.10), rgb(255, 120, 90, 0.22))
            case .night: return (rgb(96, 100, 200, 0.22), rgb(60, 64, 140, 0.12), rgb(120, 124, 210, 0.18))
            }
        } else {
            switch phase {
            case .day:   return (rgb(255, 180, 60, 0.16), rgb(255, 150, 70, 0.06), rgb(255, 180, 60, 0.26))
            case .dawn:  return (rgb(255, 150, 110, 0.16), rgb(255, 110, 90, 0.06), rgb(255, 150, 110, 0.26))
            case .dusk:  return (rgb(255, 120, 90, 0.16), rgb(255, 90, 70, 0.06), rgb(255, 120, 90, 0.26))
            case .night: return (rgb(96, 100, 200, 0.12), rgb(60, 64, 140, 0.05), rgb(96, 100, 200, 0.22))
            }
        }
    }
}

/// Hero text colors are always white at fixed opacities regardless of appearance (README §C).
enum DaybreakHeroText {
    static let primary = Color.white
    static let eyebrow = rgb(255, 255, 255, 0.72)
    static let subline = rgb(255, 255, 255, 0.82)
    static let period = rgb(255, 255, 255, 0.82)
}
