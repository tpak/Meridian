// Copyright © 2026 Chris Tirpak
//
// DaybreakScrubber — the time-travel control (README §F). A readout pill, ‹ › nudge buttons, and a
// ruler of major + minor hashes with a draggable sun/moon handle. The handle's glyph reflects the
// current location's phase; dragging sets the travel offset (snapped via the view model). The
// decorative rainbow band and the dated day labels from the prototype are intentionally dropped —
// the ruler is a plain major/minor hash scale and only the handle carries position.

import SwiftUI

struct DaybreakScrubber: View {
    let data: DaybreakScrubberData
    let palette: DaybreakPalette
    var onScrubFraction: (Double) -> Void
    var onNudge: (_ forward: Bool) -> Void
    var onReset: () -> Void

    /// Ruler band height. The chevrons are the same height, so the HStack centres them on the ruler.
    private let trackHeight: CGFloat = 30
    private let handleDiameter: CGFloat = 21
    /// Vertical centre of the ruler within `trackHeight`; everything (line, hashes, handle) sits on it.
    private var baselineY: CGFloat { trackHeight / 2 }
    /// Minor-hash count across the ruler (design comb ≈ 32 divisions). Every 8th, offset by 4, is a
    /// taller/brighter major hash → 4 evenly inset majors (12.5 / 37.5 / 62.5 / 87.5%), like the design.
    private let combDivisions = 32

    var body: some View {
        VStack(spacing: 0) {
            readoutPill
                .padding(.bottom, 11)

            HStack(spacing: 11) {
                chevron("‹", forward: false)
                track
                chevron("›", forward: true)
            }
            .frame(maxWidth: .infinity)

            // The reset link appears ONLY while traveling. It pushes the footer down and the popover
            // grows downward to make room — the panel controller re-fits the window anchored at its
            // top edge, so the hero never reflows. README §F.
            if data.traveling {
                Button(action: onReset) {
                    Text(String(localized: "↺ Back to now"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 13, trailing: 16))
    }

    private var readoutPill: some View {
        Text(data.readout)
            .font(.system(size: 11.5, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 13)
            .background(Capsule().fill(data.traveling ? palette.accent : palette.readoutIdleBackground))
            .foregroundStyle(data.traveling ? palette.onAccent : palette.textSecondary)
    }

    private func chevron(_ symbol: String, forward: Bool) -> some View {
        Button { onNudge(forward) } label: {
            Text(symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(palette.chevronButtonBackground))
                .overlay(Circle().stroke(palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(forward ? String(localized: "Forward \(stepDescription)") : String(localized: "Back \(stepDescription)"))
    }

    private var stepDescription: String {
        let step = data.stepMinutes
        if step % 60 == 0 {
            let h = step / 60
            return h == 1 ? String(localized: "\(h) hour") : String(localized: "\(h) hours")
        }
        return String(localized: "\(step) minutes")
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let handleX = data.handleFraction * w

            ZStack(alignment: .topLeading) {
                // Centerline.
                Rectangle().fill(palette.tick)
                    .frame(width: w, height: 1)
                    .offset(y: baselineY)

                // Ruler hashes: a fine comb of MINOR ticks with taller, brighter MAJOR ticks at even
                // intervals — the design's "major + minor hash" scale. Decorative (no day labels);
                // only the handle carries position. Every hash is centred on the baseline.
                ForEach(0..<combDivisions, id: \.self) { i in
                    let isMajor = i % 8 == 4
                    Rectangle().fill(isMajor ? palette.dayTick : palette.tick)
                        .frame(width: 1, height: isMajor ? 14 : 10)
                        .offset(x: CGFloat(i) / CGFloat(combDivisions) * w, y: baselineY - (isMajor ? 7 : 5))
                }

                // Handle stem + disc, centred on the baseline.
                Rectangle().fill(palette.accent).opacity(0.45)
                    .frame(width: 2, height: 16)
                    .offset(x: handleX - 1, y: baselineY - 8)
                SunMoonDisc(isNight: data.handleIsNight, diameter: handleDiameter, context: .handle, isDark: palette.isDark)
                    .overlay(Circle().stroke(handleRing, lineWidth: 2))
                    .offset(x: handleX - handleDiameter / 2, y: baselineY - handleDiameter / 2)
            }
            // Pin the ruler content to the top of the band so `baselineY` is measured from y=0 (true
            // centre). Without `.topLeading` the frame centres the content block (≈ the 21pt disc) and
            // the whole ruler drifts down ~5pt, leaving the chevrons sitting visibly ABOVE the line.
            .frame(width: w, height: trackHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                // Require a real drag (not a bare tap/click) to scrub. With minimumDistance 0 a stray
                // click anywhere on the panel that landed here teleported the handle and silently put
                // the panel into time-travel, so the current location stopped matching the system
                // clock. A deliberate drag of the handle still scrubs; ‹ › nudge for fine steps.
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        guard w > 0 else { return }
                        onScrubFraction(value.location.x / w)
                    }
            )
        }
        .frame(height: trackHeight)
    }

    private var handleRing: Color {
        palette.isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.15)
    }
}
