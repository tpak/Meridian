// Copyright © 2026 Chris Tirpak
//
// AppearancePane — the v4 Settings "Appearance" detail pane. Theme, the F1 livery
// accent grid, time/day formatting, sunrise·sunset, text size, and a live preview
// row. Mirrors the design handoff's right-aligned 150pt label column + control rows.
// Binds directly to @AppStorage; the accent passed in tints active controls.

import SwiftUI

struct AppearancePane: View {
    let accent: Color

    @AppStorage("defaultTheme") private var theme: Theme = .light
    @AppStorage("com.tpak.meridian.teamAccent") private var teamAccent: TeamAccent = .astonMartin
    @AppStorage("timeFormat") private var timeFormat: TimeFormat = .twelveHour
    @AppStorage("relativeDate") private var dayDisplay: RelativeDateDisplay = .relative
    @AppStorage("showSunriseSunset") private var showSunriseSunset = false // matches AppDefaults
    @AppStorage(DaybreakDefaults.Keys.textScale) private var textScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            FormRow(label: String(localized: "Theme")) { themeSegment }
                .padding(.bottom, 16)

            accentRow
                .padding(.bottom, 18)

            FormRow(label: String(localized: "Time format")) { timeFormatSegment }
                .padding(.bottom, 16)

            FormRow(label: String(localized: "Day display")) { dayDisplaySegment }
                .padding(.bottom, 16)

            FormRow(label: String(localized: "Sunrise / sunset")) {
                Toggle("", isOn: $showSunriseSunset)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
            }
            .padding(.bottom, 16)

            FormRow(label: String(localized: "Text size")) { textSizeSlider }
                .padding(.bottom, 22)

            previewSection
        }
    }

    // MARK: Header

    private var header: some View {
        // Spec: Appearance heading has no subtitle paragraph, just the 18pt bottom margin.
        Text(String(localized: "Appearance"))
            .font(.system(size: 20, weight: .bold))
            .padding(.bottom, 18)
    }

    // MARK: Segments

    private var themeSegment: some View {
        SegmentedControl(
            options: [(Theme.system, String(localized: "Auto")), (.light, String(localized: "Light")), (.dark, String(localized: "Dark"))],
            selection: $theme,
            accent: accent
        )
    }

    private var timeFormatSegment: some View {
        // Four options now that the seconds formats are back; the "… with
        // seconds" labels are too long for a single 4-up strip, so the same
        // segment cells wrap into a 2×2 grid (columns = hour style, rows =
        // seconds on/off). Container + cell styling match the other rows.
        SegmentedControl(
            options: [
                (TimeFormat.twelveHour, String(localized: "12-hour")),
                (.twentyFourHour, String(localized: "24-hour")),
                (.twelveHourWithSeconds, String(localized: "12-hour with seconds")),
                (.twentyFourHourWithSeconds, String(localized: "24-hour with seconds"))
            ],
            selection: $timeFormat,
            accent: accent,
            columns: 2
        )
    }

    private var dayDisplaySegment: some View {
        SegmentedControl(
            options: [
                (RelativeDateDisplay.relative, String(localized: "Relative")),
                (.actual, String(localized: "Actual")),
                (.date, String(localized: "Date")),
                (.hidden, String(localized: "Hide"))
            ],
            selection: $dayDisplay,
            accent: accent
        )
    }

    // MARK: Accent grid

    private var accentRow: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(String(localized: "Accent color"))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 8) {
                accentSwatches
                Text(String(localized: "\(teamAccent.displayName) · livery palette"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                liveryDisclaimer
            }
        }
    }

    private var accentSwatches: some View {
        let columns = [GridItem(.adaptive(minimum: 26, maximum: 26), spacing: 9)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
            ForEach(TeamAccent.allCases, id: \.self) { team in
                AccentSwatch(
                    team: team,
                    isSelected: team == teamAccent,
                    ringColor: accent
                ) {
                    teamAccent = team
                    NSApp.mer_invalidateAccentEverywhere()
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var liveryDisclaimer: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(Self.disclaimerText)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.top, 1)
    }

    // swiftlint:disable:next line_length
    private static let disclaimerText = String(localized: "Palette names & colors are stylized tributes for personalization only. Team names and liveries are trademarks of their respective Formula 1 teams — all rights reserved. Meridian is not affiliated with or endorsed by them.")

    // MARK: Text size

    private var textSizeSlider: some View {
        HStack(spacing: 12) {
            Slider(value: $textScale, in: 0.85 ... 1.3, step: 0.05)
                .tint(accent)
                .frame(maxWidth: 280)
            Text("\(Int((textScale * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "PREVIEW"))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            PreviewCard(
                timeFormat: timeFormat,
                dayDisplay: dayDisplay,
                showSun: showSunriseSunset,
                textScale: textScale,
                accent: accent
            )
        }
    }
}

// MARK: - Reusable form row

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Segmented control

private struct SegmentedControl<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    let accent: Color
    /// When set, the segments wrap into a fixed-column grid of equal-width
    /// cells instead of a single row — for rows whose labels don't fit a
    /// one-line strip (Time format's "… with seconds" options). Nil keeps
    /// the classic single-row layout.
    var columns: Int?

    var body: some View {
        segmentLayout
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    @ViewBuilder private var segmentLayout: some View {
        if let columns {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
                segments(fillWidth: true)
            }
            .frame(maxWidth: 340)
        } else {
            HStack(spacing: 2) {
                segments(fillWidth: false)
            }
        }
    }

    private func segments(fillWidth: Bool) -> some View {
        ForEach(options, id: \.0) { value, label in
            let isSelected = value == selection
            Button { selection = value } label: {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: fillWidth ? .infinity : nil)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? accent : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Accent swatch

private struct AccentSwatch: View {
    let team: TeamAccent
    let isSelected: Bool
    let ringColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: team.accentColor))
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? ringColor : .clear, lineWidth: 2)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .help(team.displayName)
        .accessibilityLabel(team.displayName)
    }
}

// MARK: - Live preview card

private struct PreviewCard: View {
    let timeFormat: TimeFormat
    let dayDisplay: RelativeDateDisplay
    let showSun: Bool
    let textScale: Double
    let accent: Color

    private var timeString: String {
        switch timeFormat {
        case .twentyFourHour: return "20:17"
        case .twentyFourHourWithSeconds: return "20:17:45"
        case .twelveHourWithSeconds: return "8:17:45 PM"
        // .twelveHour, plus the legacy formats the picker doesn't offer.
        default: return "8:17 PM"
        }
    }

    private var subString: String {
        switch dayDisplay {
        case .relative: return "−16h · yesterday"
        case .actual:   return "Sun 8:17 PM"
        case .date:     return "Sun 12 Jun"
        case .hidden:   return ""
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.12), accent.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var leading: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(accent)
                .frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text("Denver")
                    .font(.system(size: 15 * textScale, weight: .medium))
                if !subString.isEmpty {
                    Text(subString)
                        .font(.system(size: 11.5 * textScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(timeString)
                .font(.system(size: 21 * textScale, weight: .semibold).monospacedDigit())
            if showSun {
                Text("↓ Sunset 8:28 PM")
                    .font(.system(size: 11.5 * textScale))
                    .foregroundStyle(accent)
            }
        }
    }
}
