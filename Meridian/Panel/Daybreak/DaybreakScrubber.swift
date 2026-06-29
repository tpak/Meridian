// Copyright © 2026 Chris Tirpak
//
// DaybreakScrubber — the time-travel control (README §F). A readout pill, ‹ › nudge buttons, and a
// ruler of major + minor hashes with a draggable sun/moon handle.
//
// EXPERIMENT (branch `experiment/scrubber-treadmill`): the ruler is a *treadmill*. Instead of mapping
// the handle's absolute position to the entire Travel range — which crams many days into a few pixels
// and makes the drag hyper-sensitive — the handle tracks a fixed visible window (±`visibleHalfSpan`)
// and then PINS to the edge while the tick ruler scrolls underneath it. Drag sensitivity is therefore
// constant (one day is always the same finger distance) no matter how large the Travel range is, and
// the scrolling ticks plus the accent "now" marker convey the sense of movement. The readout pill
// remains the precise position; the ‹ › buttons step an exact snap-step.

import SwiftUI

struct DaybreakScrubber: View {
    let data: DaybreakScrubberData
    let palette: DaybreakPalette
    /// Set the absolute travel offset (minutes). The view computes this from a *relative* drag, so
    /// sensitivity no longer depends on the total range. The view model clamps + snaps.
    var onScrubToOffset: (Int) -> Void
    var onNudge: (_ forward: Bool) -> Void
    var onReset: () -> Void

    /// Ruler band height. The chevrons are the same height, so the HStack centres them on the ruler.
    private let trackHeight: CGFloat = 30
    private let handleDiameter: CGFloat = 21
    /// Vertical centre of the ruler within `trackHeight`; everything (line, hashes, handle) sits on it.
    private var baselineY: CGFloat { trackHeight / 2 }

    /// Minutes from the ruler's centre to each visible edge. The handle reaches the edge after this
    /// much travel; beyond it the handle pins and the ruler scrolls. One day is a deliberate, legible
    /// rate — this single constant tunes the whole feel.
    private let visibleHalfSpanMinutes = 1440

    /// Tracks the offset at the moment a drag began, so each `onChanged` maps the *cumulative*
    /// translation to a new absolute offset (stable even as the published offset updates mid-drag).
    @State private var dragStartOffset: Int?

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
            let pxPerMinute = (w / 2) / CGFloat(visibleHalfSpanMinutes)
            let offset = data.offsetMinutes
            // The handle moves within ±visibleHalfSpan, then pins to the edge.
            let dotDisplacementMin = max(-visibleHalfSpanMinutes, min(visibleHalfSpanMinutes, offset))
            let dotX = w / 2 + CGFloat(dotDisplacementMin) * pxPerMinute
            // Traveled-minutes value sitting at the viewport centre. 0 while the handle is still inside
            // the window (ruler fixed, handle moves); grows once the handle pins (ruler scrolls).
            let centerTimeMin = offset - dotDisplacementMin

            ZStack(alignment: .topLeading) {
                // Centerline + scrolling ticks, faded at the edges for the treadmill feel. The handle
                // is drawn OUTSIDE this mask so it stays crisp even when pinned at an edge.
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(palette.tick)
                        .frame(width: w, height: 1)
                        .offset(y: baselineY)
                    tickMarks(w: w, pxPerMinute: pxPerMinute, centerTimeMin: centerTimeMin)
                }
                .mask(edgeFade)

                // Handle stem + disc at the computed dot position.
                Rectangle().fill(palette.accent).opacity(0.45)
                    .frame(width: 2, height: 16)
                    .offset(x: dotX - 1, y: baselineY - 8)
                SunMoonDisc(isNight: data.handleIsNight, diameter: handleDiameter, context: .handle, isDark: palette.isDark)
                    .overlay(Circle().stroke(handleRing, lineWidth: 2))
                    .offset(x: dotX - handleDiameter / 2, y: baselineY - handleDiameter / 2)
            }
            .frame(width: w, height: trackHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                // Relative drag: cumulative translation → minutes at a CONSTANT px/minute rate, added
                // to the offset captured at drag start. A real drag (≥4pt) is required so a stray click
                // can't teleport the handle / silently enter time-travel.
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard pxPerMinute > 0 else { return }
                        let start = dragStartOffset ?? offset
                        if dragStartOffset == nil { dragStartOffset = start }
                        let deltaMin = Int((value.translation.width / pxPerMinute).rounded())
                        onScrubToOffset(start + deltaMin)
                    }
                    .onEnded { _ in dragStartOffset = nil }
            )
        }
        .frame(height: trackHeight)
    }

    /// Ruler hashes anchored to absolute traveled-time, so they slide under the handle as it pins and
    /// the window scrolls. Minor ticks at a legible cadence (≥ the snap step), taller MAJOR ticks at
    /// day boundaries, and an accent "now" tick at offset 0 — the reference that scrolls away as you
    /// travel, giving the sense of movement.
    @ViewBuilder
    private func tickMarks(w: CGFloat, pxPerMinute: CGFloat, centerTimeMin: Int) -> some View {
        let minorMin = minorTickMinutes(pxPerMinute: pxPerMinute)
        let half = visibleHalfSpanMinutes
        let lo = centerTimeMin - half
        let hi = centerTimeMin + half
        let firstK = Int((Double(lo) / Double(minorMin)).rounded(.up))
        let lastK = Int((Double(hi) / Double(minorMin)).rounded(.down))
        if firstK <= lastK {
            ForEach(Array(firstK...lastK), id: \.self) { k in
                let t = k * minorMin
                let x = w / 2 + CGFloat(t - centerTimeMin) * pxPerMinute
                let isNow = t == 0
                let isDay = t % 1440 == 0
                let height: CGFloat = isNow ? 16 : (isDay ? 14 : 10)
                let color = isNow ? palette.accent : (isDay ? palette.dayTick : palette.tick)
                Rectangle().fill(color)
                    .frame(width: isNow ? 2 : 1, height: height)
                    .offset(x: x - (isNow ? 1 : 0.5), y: baselineY - height / 2)
            }
        }
    }

    /// Smallest "nice" minute interval whose on-screen spacing is legible (≥ 9pt), never finer than the
    /// snap step. Keeps the ruler readable whether the step is 5 or 60 minutes.
    private func minorTickMinutes(pxPerMinute: CGFloat) -> Int {
        let candidates = [data.stepMinutes, 15, 30, 60, 120, 180, 360, 720, 1440].filter { $0 >= data.stepMinutes }
        return candidates.first { CGFloat($0) * pxPerMinute >= 9 } ?? 1440
    }

    /// Horizontal fade so ticks dissolve in/out at the track ends — reinforces the treadmill scroll.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.07),
                .init(color: .black, location: 0.93),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var handleRing: Color {
        palette.isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.15)
    }
}
