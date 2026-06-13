// Copyright © 2026 Chris Tirpak
//
// TimeTravelPane — Settings > Time Travel pane for the v4 NavigationSplitView window.
// Controls scrubber range (forward / back), arrow/snap step, and the Time Scroller toggle.

import SwiftUI

struct TimeTravelPane: View {
    let accent: Color

    @AppStorage("sliderDayRange") private var forwardDays = 6
    @AppStorage("com.tpak.meridian.v4.travelPastDays") private var backDays = 2
    @AppStorage("com.tpak.meridian.v4.snapStep") private var snapStep = 15
    @AppStorage("showFutureSlider") private var showFutureSlider = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Spacer(minLength: 20)
            formRows
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time Travel")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
            Text("Limits and feel of the scrubber in the popover.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Form rows

    private var formRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForwardDaysRow(accent: accent, forwardDays: $forwardDays)
                .padding(.bottom, 8)
            BackDaysRow(accent: accent, backDays: $backDays)
                .padding(.bottom, 18)
            SnapStepRow(accent: accent, snapStep: $snapStep)
                .padding(.bottom, 16)
            ShowScrollerRow(accent: accent, showFutureSlider: $showFutureSlider)
        }
    }
}

// MARK: - Forward days row

private struct ForwardDaysRow: View {
    let accent: Color
    @Binding var forwardDays: Int

    private var doubleBinding: Binding<Double> {
        Binding(get: { Double(forwardDays) }, set: { forwardDays = Int($0) })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FormLabel("Travel forward")
            Slider(value: doubleBinding, in: 1...30, step: 1)
                .tint(accent)
                .frame(maxWidth: .infinity)
            readout("\(forwardDays) day\(forwardDays == 1 ? "" : "s")")
        }
    }
}

// MARK: - Back days row

private struct BackDaysRow: View {
    let accent: Color
    @Binding var backDays: Int

    private var doubleBinding: Binding<Double> {
        Binding(get: { Double(backDays) }, set: { backDays = Int($0) })
    }

    private var label: String { backDays == 0 ? "Off" : "\(backDays) day\(backDays == 1 ? "" : "s")" }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FormLabel("Travel back")
            Slider(value: doubleBinding, in: 0...7, step: 1)
                .tint(accent)
                .frame(maxWidth: .infinity)
            readout(label)
        }
    }
}

// MARK: - Snap step row

private struct SnapStepRow: View {
    let accent: Color
    @Binding var snapStep: Int

    private let options: [(value: Int, label: String)] = [
        (5, "5 min"), (15, "15 min"), (30, "30 min"), (60, "60 min")
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FormLabel("Arrow / snap step")
            segmentedControl
            Spacer()
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                SnapSegmentButton(
                    label: option.label,
                    isSelected: snapStep == option.value,
                    accent: accent
                ) {
                    snapStep = option.value
                }
            }
        }
        .padding(2)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
        .cornerRadius(8)
    }
}

private struct SnapSegmentButton: View {
    let label: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? accent : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Show scroller row

private struct ShowScrollerRow: View {
    let accent: Color
    @Binding var showFutureSlider: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FormLabel("Show Time Scroller")
            Toggle("", isOn: $showFutureSlider)
                .toggleStyle(.switch)
                .tint(accent)
                .labelsHidden()
            Spacer()
        }
    }
}

// MARK: - Shared helpers

/// Right-aligned 150pt label column matching the design's form-row layout.
private struct FormLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .trailing)
    }
}

/// Fixed-width readout for slider values (tabular numerics, 64pt column).
private func readout(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12.5).monospacedDigit())
        .foregroundStyle(.primary)
        .frame(width: 64, alignment: .leading)
}
