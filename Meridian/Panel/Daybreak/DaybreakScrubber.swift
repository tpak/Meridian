// Copyright © 2026 Chris Tirpak
//
// DaybreakScrubber — the time-travel control (README §F). A readout pill, ‹ › nudge buttons, and a
// ruler of major + minor hashes with a draggable sun/moon handle.
//
// EXPERIMENT (branch `experiment/scrubber-treadmill`): the ruler is a *treadmill*. Instead of mapping
// the handle's absolute position to the entire Travel range — which crammed many days into a few
// pixels and made the drag hyper-sensitive — the handle tracks a fixed visible window (±`visibleHalfSpan`)
// then PINS a couple of ticks short of the edge while the tick ruler scrolls underneath it. Drag
// sensitivity is therefore constant (one day is always the same finger distance) no matter how large
// the Travel range is, and the scrolling ticks plus the accent "now" marker convey movement.
//
// The track drag is handled by a small AppKit surface (`ScrubberDragSurface`) rather than a SwiftUI
// gesture, for two reasons: (1) the floating popover sets `isMovableByWindowBackground`, which steals
// a SwiftUI drag to move the window — the AppKit view declares `mouseDownCanMoveWindow = false` so the
// handle stays draggable while floating; (2) it owns a timer, so holding the handle at an edge keeps
// scrolling (with edge feedback) instead of dead-stopping until you reach for the ‹ › buttons.

import SwiftUI
import AppKit

struct DaybreakScrubber: View {
    let data: DaybreakScrubberData
    let palette: DaybreakPalette
    /// Set the absolute travel offset (minutes). Computed from a *relative* drag, so sensitivity no
    /// longer depends on the total range. The view model clamps + snaps.
    var onScrubToOffset: (Int) -> Void
    var onNudge: (_ forward: Bool) -> Void
    var onReset: () -> Void

    /// Ruler band height. The chevrons are the same height, so the HStack centres them on the ruler.
    private let trackHeight: CGFloat = 30
    private let handleDiameter: CGFloat = 21
    /// Vertical centre of the ruler within `trackHeight`; everything (line, hashes, handle) sits on it.
    private var baselineY: CGFloat { trackHeight / 2 }

    /// Minutes from the ruler's centre to each visible edge. The handle reaches its pinned position
    /// after this much travel; beyond it the ruler scrolls. One day is a deliberate, legible rate —
    /// this single constant tunes the whole feel.
    private let visibleHalfSpanMinutes = 1440

    /// Keep the handle this far from the track ends so its disc never overlaps the ‹ › arrows
    /// (≈ two tick marks of breathing room, as requested).
    private let edgeBuffer: CGFloat = 18

    /// Live edge-scroll feedback from the AppKit drag surface: -1 scrolling back, +1 forward, 0 idle;
    /// `edgeAtLimit` when the Travel range end has been reached and it can't scroll further.
    @State private var edgeDir = 0
    @State private var edgeAtLimit = false

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
            // The handle moves within ±visibleHalfSpan, then pins a couple of ticks short of the edge.
            let dotDisplacementMin = max(-visibleHalfSpanMinutes, min(visibleHalfSpanMinutes, offset))
            let rawDotX = w / 2 + CGFloat(dotDisplacementMin) * pxPerMinute
            let dotX = min(w - edgeBuffer, max(edgeBuffer, rawDotX))
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

                edgeGlow(w: w)

                // Handle stem + disc at the computed dot position.
                Rectangle().fill(palette.accent).opacity(0.45)
                    .frame(width: 2, height: 16)
                    .offset(x: dotX - 1, y: baselineY - 8)
                SunMoonDisc(isNight: data.handleIsNight, diameter: handleDiameter, context: .handle, isDark: palette.isDark)
                    .overlay(Circle().stroke(handleRing, lineWidth: 2))
                    .offset(x: dotX - handleDiameter / 2, y: baselineY - handleDiameter / 2)

                // AppKit drag surface on top (transparent): owns the scrub drag + edge auto-scroll and
                // keeps the handle draggable while the popover is floating.
                ScrubberDragSurface(
                    visibleHalfSpanMinutes: visibleHalfSpanMinutes,
                    stepMinutes: data.stepMinutes,
                    offsetMinutes: offset,
                    rangeLower: data.rangeLowerBound,
                    rangeUpper: data.rangeUpperBound,
                    setOffset: onScrubToOffset,
                    onEdge: { dir, atLimit in
                        edgeDir = dir
                        edgeAtLimit = atLimit
                    }
                )
            }
            .frame(width: w, height: trackHeight, alignment: .topLeading)
            .contentShape(Rectangle())
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
                let kind = TickKind(minutesFromNow: t)
                Rectangle().fill(tickColor(kind))
                    .frame(width: kind.width, height: kind.height)
                    .offset(x: x - kind.width / 2, y: baselineY - kind.height / 2)
            }
        }
    }

    /// Visual weight of a ruler tick. `now` is the accent marker at the current time, `day` marks a
    /// midnight boundary, and `minor` is every other hash. Replaces a pair of nested ternaries that
    /// both branched on the same two flags (Sonar swift:S3358).
    private enum TickKind {
        case now, day, minor

        init(minutesFromNow minutes: Int) {
            if minutes == 0 {
                self = .now
            } else if minutes % 1440 == 0 {
                self = .day
            } else {
                self = .minor
            }
        }

        var height: CGFloat {
            switch self {
            case .now: return 16
            case .day: return 14
            case .minor: return 10
            }
        }

        var width: CGFloat {
            switch self {
            case .now: return 2
            case .day, .minor: return 1
            }
        }
    }

    private func tickColor(_ kind: TickKind) -> Color {
        switch kind {
        case .now: return palette.accent
        case .day: return palette.dayTick
        case .minor: return palette.tick
        }
    }

    /// Smallest "nice" minute interval whose on-screen spacing is legible (≥ 9pt), never finer than the
    /// snap step. Keeps the ruler readable whether the step is 5 or 60 minutes.
    private func minorTickMinutes(pxPerMinute: CGFloat) -> Int {
        let candidates = [data.stepMinutes, 15, 30, 60, 120, 180, 360, 720, 1440].filter { $0 >= data.stepMinutes }
        return candidates.first { CGFloat($0) * pxPerMinute >= 9 } ?? 1440
    }

    /// Accent glow at the active edge while auto-scrolling; a brighter solid bar when the Travel range
    /// end is reached, so "still scrolling" and "that's as far as it goes" read differently.
    @ViewBuilder
    private func edgeGlow(w: CGFloat) -> some View {
        if edgeDir != 0 {
            let leading = edgeDir < 0
            let barWidth: CGFloat = edgeAtLimit ? 4 : 14
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: edgeAtLimit
                            ? [palette.accent, palette.accent]
                            : [palette.accent.opacity(0.55), palette.accent.opacity(0)],
                        startPoint: leading ? .leading : .trailing,
                        endPoint: leading ? .trailing : .leading
                    )
                )
                .frame(width: barWidth, height: trackHeight)
                .offset(x: leading ? 0 : w - barWidth)
        }
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

// MARK: - AppKit drag surface

/// A transparent AppKit overlay that handles the scrubber's drag. Using AppKit (not a SwiftUI gesture)
/// lets us (1) keep the handle draggable while the floating popover has `isMovableByWindowBackground`
/// on — by declaring `mouseDownCanMoveWindow = false` — and (2) run an auto-scroll timer so holding at
/// an edge keeps traveling. The visuals (ticks, handle, glow) are drawn by SwiftUI underneath.
private struct ScrubberDragSurface: NSViewRepresentable {
    let visibleHalfSpanMinutes: Int
    let stepMinutes: Int
    let offsetMinutes: Int
    let rangeLower: Int
    let rangeUpper: Int
    let setOffset: (Int) -> Void
    let onEdge: (Int, Bool) -> Void

    func makeNSView(context: Context) -> ScrubberDragNSView {
        let view = ScrubberDragNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ScrubberDragNSView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: ScrubberDragNSView) {
        view.visibleHalfSpanMinutes = visibleHalfSpanMinutes
        view.stepMinutes = stepMinutes
        view.liveOffset = offsetMinutes
        view.rangeLower = rangeLower
        view.rangeUpper = rangeUpper
        view.setOffset = setOffset
        view.onEdge = onEdge
    }
}

private final class ScrubberDragNSView: NSView {
    var visibleHalfSpanMinutes = 1440
    var stepMinutes = 15
    var liveOffset = 0
    var rangeLower = 0
    var rangeUpper = 0
    var setOffset: (Int) -> Void = { _ in }
    var onEdge: (Int, Bool) -> Void = { _, _ in }

    private var dragStartOffset = 0
    private var dragStartX: CGFloat = 0
    private var autoTimer: Timer?
    private var autoDir = 0
    /// Local accumulator while auto-scrolling, so progress doesn't depend on the SwiftUI offset
    /// round-trip landing between timer ticks.
    private var autoOffset = 0

    /// The whole point: don't let a drag here move the floating window.
    override var mouseDownCanMoveWindow: Bool { false }
    /// Respond on the first click even when the floating panel isn't key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let edgeZone: CGFloat = 24

    private var pxPerMinute: CGFloat {
        let half = CGFloat(max(1, visibleHalfSpanMinutes))
        return (bounds.width / 2) / half
    }

    override func mouseDown(with event: NSEvent) {
        rebase(at: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard pxPerMinute > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let w = bounds.width

        if x >= w - edgeZone {
            beginAutoScroll(dir: 1)
        } else if x <= edgeZone {
            beginAutoScroll(dir: -1)
        } else {
            if autoTimer != nil { stopAutoScroll(); rebase(at: x) }   // resume relative drag without a jump
            let deltaMin = Int(((x - dragStartX) / pxPerMinute).rounded())
            setOffset(clampToRange(dragStartOffset + deltaMin))
        }
    }

    override func mouseUp(with event: NSEvent) {
        stopAutoScroll()
    }

    private func rebase(at x: CGFloat) {
        dragStartOffset = liveOffset
        dragStartX = x
    }

    private func clampToRange(_ value: Int) -> Int { min(rangeUpper, max(rangeLower, value)) }

    private func atLimit(_ value: Int, _ dir: Int) -> Bool {
        dir > 0 ? value >= rangeUpper : value <= rangeLower
    }

    private func beginAutoScroll(dir: Int) {
        if autoDir == dir, autoTimer != nil { return }
        stopAutoScroll()
        autoDir = dir
        autoOffset = liveOffset
        onEdge(dir, atLimit(autoOffset, dir))
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.autoTick() }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
    }

    private func autoTick() {
        // ~1 day per second, but never less than one snap step per tick.
        let perTick = max(stepMinutes, Int((1440.0 * 0.04).rounded()))
        autoOffset = clampToRange(autoOffset + autoDir * perTick)
        setOffset(autoOffset)
        onEdge(autoDir, atLimit(autoOffset, autoDir))
    }

    private func stopAutoScroll() {
        autoTimer?.invalidate()
        autoTimer = nil
        if autoDir != 0 {
            autoDir = 0
            onEdge(0, false)
        }
    }
}
