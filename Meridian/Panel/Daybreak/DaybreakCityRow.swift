// Copyright © 2026 Chris Tirpak
//
// DaybreakCityRow — one tracked-city card. Left: sun/moon disc, name (+ optional ⌂ Home badge),
// and the next-sun-event sub-label (swaps to a UTC line on hover). Right: the city's time and its
// offset relative to the current location. Double-click the time to edit (README §A/§B/§D/§E).

import SwiftUI

struct DaybreakCityRow: View {
    let city: DaybreakCityData
    let palette: DaybreakPalette
    let isEditing: Bool
    @Binding var editText: String
    var onBeginEdit: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        let tint = DaybreakTints.card(for: city.phase, isDark: palette.isDark)
        return HStack(spacing: 12) {
            SunMoonDisc(isNight: city.isNight, diameter: 23, context: .row, isDark: palette.isDark)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(city.name)
                        .font(DaybreakFont.text(14.5, 580))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if city.isHome {
                        Text("⌂")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.hairline, lineWidth: 1))
                            .help("Home")
                    }
                }
                Text(hovering ? city.hoverLabel : city.nextEventLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(hovering ? palette.accent : palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                timeView
                Text(city.offsetLabel)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.border, lineWidth: 1))
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var timeView: some View {
        if isEditing {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .focused($focused)
                .frame(width: 96)
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(palette.editFieldBackground))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.editFieldBorder, lineWidth: 1))
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
                .onChange(of: focused) { _, isFocused in if !isFocused { onCommit() } }
                .onAppear { focused = true }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(city.time)
                    .font(DaybreakFont.digit(20, 600))
                    .tracking(20 * -0.02)
                    .foregroundStyle(palette.text)
                if !city.period.isEmpty {
                    Text(city.period)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onBeginEdit)
            .help("Double-click to set this time")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(city.name). \(city.time) \(city.period). \(city.offsetLabel). \(city.nextEventLabel)")
        }
    }
}
