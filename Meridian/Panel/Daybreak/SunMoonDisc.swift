// Copyright © 2026 Chris Tirpak
//
// SunMoonDisc — the gradient disc that appears on the hero, on each city row, and on the scrubber
// handle. A moon when the city's phase is night, otherwise a sun (README §B). The disc is purely a
// radial gradient + glow (no drawn rays/craters) — matching the prototype.

import SwiftUI

struct SunMoonDisc: View {
    let isNight: Bool
    let diameter: CGFloat
    var context: SunMoonStyle.Context = .row
    var isDark: Bool

    var body: some View {
        let glow = SunMoonStyle.glow(isNight: isNight, context: context, isDark: isDark)
        Circle()
            .fill(SunMoonStyle.gradient(isNight: isNight, diameter: diameter))
            .frame(width: diameter, height: diameter)
            .shadow(color: glow.color, radius: glow.radius)
            .accessibilityHidden(true)
    }
}
