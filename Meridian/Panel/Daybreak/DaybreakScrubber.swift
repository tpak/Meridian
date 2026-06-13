// Copyright © 2026 Chris Tirpak
//
// DaybreakScrubber — the time-travel control (README §F). A readout pill, ‹ › nudge buttons, and a
// tick ruler with day-boundary markers and a draggable sun/moon handle. The handle's glyph reflects
// the current location's phase; dragging sets the travel offset (snapped via the view model). The
// decorative rainbow band from the prototype is intentionally dropped — the ruler + handle remain.

import SwiftUI

struct DaybreakScrubber: View {
    let data: DaybreakScrubberData
    let palette: DaybreakPalette
    var onScrubFraction: (Double) -> Void
    var onNudge: (_ forward: Bool) -> Void
    var onReset: () -> Void

    private let trackHeight: CGFloat = 40
    private let handleDiameter: CGFloat = 21
    private let baselineY: CGFloat = 20

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

            if data.traveling {
                Button(action: onReset) {
                    Text("↺ Back to now")
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
        .help(forward ? "Forward \(stepDescription)" : "Back \(stepDescription)")
    }

    private var stepDescription: String { "15 minutes" }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let handleX = data.handleFraction * w

            ZStack(alignment: .topLeading) {
                // Centerline.
                Rectangle().fill(palette.tick)
                    .frame(width: w, height: 1)
                    .offset(y: baselineY)

                // Hour-aligned ruler ticks. Plain hour ticks are short and faint; the 6-hourly ticks
                // (06:00/12:00/18:00) are taller and more opaque, so the ruler reads as a ruler
                // instead of a wall of identical marks. Midnight is left to the taller day marker.
                ForEach(data.ticks) { tick in
                    let tickHeight: CGFloat = tick.isMajor ? 10 : 5
                    Rectangle().fill(palette.tick)
                        .frame(width: 1, height: tickHeight)
                        .opacity(tick.isMajor ? 0.9 : 0.4)
                        .offset(x: tick.fraction * w, y: baselineY - tickHeight / 2)
                }

                // Day-boundary markers + labels.
                ForEach(data.days) { day in
                    let x = day.fraction * w
                    Rectangle().fill(palette.dayTick)
                        .frame(width: 1, height: 14)
                        .offset(x: x, y: 13)
                    Text(day.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(day.isToday ? palette.accent : palette.textTertiary)
                        .fixedSize()
                        .offset(x: x + 3, y: 28)
                }

                // Handle stem + disc.
                Rectangle().fill(palette.accent).opacity(0.45)
                    .frame(width: 2, height: 16)
                    .offset(x: handleX - 1, y: 12)
                SunMoonDisc(isNight: data.handleIsNight, diameter: handleDiameter, context: .handle, isDark: palette.isDark)
                    .overlay(Circle().stroke(handleRing, lineWidth: 2))
                    .offset(x: handleX - handleDiameter / 2, y: baselineY - handleDiameter / 2)
            }
            .frame(width: w, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
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
