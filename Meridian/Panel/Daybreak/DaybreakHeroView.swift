// Copyright © 2026 Chris Tirpak
//
// DaybreakHeroView — the top "current location" section. Big tabular time over a phase-keyed sky
// gradient, with a sun/moon disc and a next-sun-event subline that swaps to a UTC line on hover.
// Double-clicking the time enters inline edit (README §C/§E).

import SwiftUI

struct DaybreakHeroView: View {
    let hero: DaybreakHeroData
    let palette: DaybreakPalette
    var scale: CGFloat = 1
    let isEditing: Bool
    @Binding var editText: String
    var onBeginEdit: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hero.eyebrow)
                .font(.system(size: 11 * scale, weight: .semibold))
                .tracking(1.0 * scale)
                .textCase(.uppercase)
                .foregroundStyle(DaybreakHeroText.eyebrow)
                .lineLimit(1)

            timeRow
                .frame(height: 50 * scale, alignment: .center)
                .padding(.top, 5)

            Text(hovering ? hero.hoverSubline : hero.subline)
                .font(.system(size: 12.5 * scale))
                .foregroundStyle(DaybreakHeroText.subline)
                .padding(.top, 7)
                .lineLimit(1)
                .frame(minHeight: 16 * scale, alignment: .leading)
        }
        .padding(EdgeInsets(top: 18, leading: 21, bottom: 20, trailing: 21))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DaybreakSky.gradient(for: hero.phase))
        .overlay(alignment: .topTrailing) {
            SunMoonDisc(isNight: hero.isNight, diameter: 32, context: .hero, isDark: palette.isDark)
                .padding(.top, 15)
                .padding(.trailing, 19)
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var timeRow: some View {
        if isEditing {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 34 * scale, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .focused($focused)
                .frame(width: 200)
                .padding(.vertical, 2)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
                .onChange(of: focused) { _, isFocused in if !isFocused { onCommit() } }
                .onAppear { focused = true }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(hero.time)
                    .font(DaybreakFont.digit(47 * scale, 640))
                    .tracking(47 * scale * -0.03)
                    .foregroundStyle(.white)
                if !hero.period.isEmpty {
                    Text(hero.period)
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(DaybreakHeroText.period)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onBeginEdit)
            .help(String(localized: "Double-click to set this time"))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(hero.eyebrow). \(hero.time) \(hero.period). \(hero.subline)")
        }
    }
}
