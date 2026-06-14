// Copyright © 2026 Chris Tirpak
//
// MenuBarPane — v4 Settings › Menu Bar detail pane.
// Writes ONLY the pane content; the outer ScrollView + padding live in SettingsRootView.

import AppKit
import SwiftUI

// MARK: - Preset model

private struct MenuBarPreset: Identifiable {
    let id: String
    let label: String
    let sample: String
    let place: Bool
    let day: Bool
    let date: Bool
    let twentyFourHour: Bool
    let dots: Bool
}

private let menuBarPresets: [MenuBarPreset] = [
    MenuBarPreset(
        id: "compact", label: String(localized: "Compact"), sample: "IST 7:47 AM",
        place: true, day: false, date: false, twentyFourHour: false, dots: true
    ),
    MenuBarPreset(
        id: "withday", label: String(localized: "With day"), sample: "IST Mon 7:47 AM",
        place: true, day: true, date: false, twentyFourHour: false, dots: true
    ),
    MenuBarPreset(
        id: "dense24", label: String(localized: "Dense · 24h"), sample: "IST 07:47",
        place: true, day: false, date: false, twentyFourHour: true, dots: true
    ),
    MenuBarPreset(
        id: "withdate", label: String(localized: "With date"), sample: "IST 7:47 AM 13 Jun",
        place: true, day: false, date: true, twentyFourHour: false, dots: true
    ),
    MenuBarPreset(
        id: "mono", label: String(localized: "Mono · no dots"), sample: "IST 7:47 AM",
        place: true, day: false, date: false, twentyFourHour: false, dots: false
    )
]

// MARK: - Preview sample data

private struct PreviewSample {
    let name: String
    let day: String
    let t12: String
    let ampm: String
    let t24: String
    let date: String
    let dotColor: Color
}

private let previewSamples: [PreviewSample] = [
    PreviewSample(
        name: "IST", day: "Mon", t12: "7:47", ampm: "AM",
        t24: "07:47", date: "13 Jun",
        dotColor: Color(red: 0.0, green: 0.63, blue: 0.61)
    ),
    PreviewSample(
        name: "Denver", day: "Sun", t12: "8:17", ampm: "PM",
        t24: "20:17", date: "12 Jun",
        dotColor: Color(red: 0.91, green: 0.0, blue: 0.18)
    )
]

// MARK: - MenuBarPane

struct MenuBarPane: View {
    let accent: Color

    // Fine-tune toggles
    @AppStorage("showPlaceNameInMenubar") private var showPlaceName = true
    @AppStorage("showDayInMenubar") private var showDay = false
    @AppStorage("showDateInMenubar") private var showDate = false
    @AppStorage("timeFormat") private var timeFormat: TimeFormat = .twelveHour
    @AppStorage("com.tpak.meridian.v4.menubarColorDots") private var menubarColorDots = true

    // Presentation + float
    @AppStorage("com.tpak.meridian.appDisplayOptions") private var appPresentation: AppPresentation = .menubarOnly
    @AppStorage("floatOnTop") private var floatOnTop = false

    // Active preset tracking
    @AppStorage("com.tpak.meridian.v4.menubarPreset") private var activePresetID = "compact"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            previewStrip
                .padding(.bottom, 22)
            presetSection
                .padding(.bottom, 24)
            fineTuneSection
            presentationRow
                .padding(.top, 4)
            floatOnTopRow
                .padding(.top, 14)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Menu Bar"))
                .font(.system(size: 20, weight: .bold))
            Text(String(localized: "How your starred cities appear up top. No app name or clock — macOS shows those."))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Live preview strip

    private var previewStrip: some View {
        HStack {
            Spacer()
            previewChips
        }
        .frame(height: 34)
        .background(Color(red: 0.08, green: 0.086, blue: 0.118).opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var previewChips: some View {
        HStack(spacing: 0) {
            ForEach(previewItems, id: \.label) { item in
                MenuBarChip(item: item)
                    .padding(.leading, 16)
            }
        }
        .padding(.trailing, 14)
    }

    private var previewItems: [PreviewChipItem] {
        previewSamples.map { sample in
            var parts: [String] = []
            if showPlaceName { parts.append(sample.name) }
            if showDay { parts.append(sample.day) }
            let time = timeFormat == .twentyFourHour ? sample.t24 : "\(sample.t12) \(sample.ampm)"
            parts.append(time)
            if showDate { parts.append(sample.date) }
            return PreviewChipItem(
                label: parts.joined(separator: " "),
                dot: sample.dotColor,
                showDot: menubarColorDots
            )
        }
    }

    // MARK: - Preset section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel(String(localized: "Preset"))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(menuBarPresets) { preset in
                    PresetCard(preset: preset, isActive: activePresetID == preset.id, accent: accent) {
                        applyPreset(preset)
                    }
                }
            }
        }
    }

    private func applyPreset(_ preset: MenuBarPreset) {
        activePresetID = preset.id
        showPlaceName = preset.place
        showDay = preset.day
        showDate = preset.date
        menubarColorDots = preset.dots
        timeFormat = preset.twentyFourHour ? .twentyFourHour : .twelveHour
    }

    // MARK: - Fine-tune section

    private var fineTuneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel(String(localized: "Fine-tune"))
            formRow(String(localized: "Place name")) {
                Toggle("", isOn: $showPlaceName)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
                    .onChange(of: showPlaceName) { _, _ in activePresetID = "custom" }
            }
            formRow(String(localized: "Day of week")) {
                Toggle("", isOn: $showDay)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
                    .onChange(of: showDay) { _, _ in activePresetID = "custom" }
            }
            formRow(String(localized: "Date")) {
                Toggle("", isOn: $showDate)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
                    .onChange(of: showDate) { _, _ in activePresetID = "custom" }
            }
            formRow(String(localized: "24-hour time")) {
                Toggle("", isOn: twentyFourBinding)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
            }
            formRow(String(localized: "Color dots")) {
                Toggle("", isOn: $menubarColorDots)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
                    .onChange(of: menubarColorDots) { _, _ in activePresetID = "custom" }
            }
        }
    }

    private var twentyFourBinding: Binding<Bool> {
        Binding(
            get: { timeFormat == .twentyFourHour },
            set: { on in
                timeFormat = on ? .twentyFourHour : .twelveHour
                activePresetID = "custom"
            }
        )
    }

    // MARK: - Show Meridian in

    private var presentationRow: some View {
        formRow(String(localized: "Show Meridian in")) {
            Picker("", selection: $appPresentation) {
                Text(String(localized: "Menu Bar only")).tag(AppPresentation.menubarOnly)
                Text(String(localized: "Dock & Menu Bar")).tag(AppPresentation.menubarAndDock)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: appPresentation) { _, newValue in
                NSApp.setActivationPolicy(newValue == .menubarAndDock ? .regular : .accessory)
            }
        }
    }

    // MARK: - Float on top

    private var floatOnTopRow: some View {
        formRow(String(localized: "Float on top")) {
            HStack(spacing: 8) {
                Toggle("", isOn: $floatOnTop)
                    .labelsHidden()
                    .toggleStyle(AccentSwitchToggleStyle(accent: accent))
                Text(String(localized: "Keep the popover open"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tertiary)
            .kerning(0.7)
    }

    private func formRow<C: View>(_ label: String, @ViewBuilder control: @escaping () -> C) -> some View {
        FormRow(label: label, control: control)
    }
}

// MARK: - FormRow

private struct FormRow<C: View>: View {
    let label: String
    let control: () -> C

    init(label: String, @ViewBuilder control: @escaping () -> C) {
        self.label = label
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
                .fixedSize()
            control()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - PreviewChipItem + MenuBarChip

private struct PreviewChipItem {
    let label: String
    let dot: Color
    let showDot: Bool
}

private struct MenuBarChip: View {
    let item: PreviewChipItem

    var body: some View {
        HStack(spacing: 5) {
            if item.showDot {
                Circle()
                    .fill(item.dot)
                    .frame(width: 5, height: 5)
            }
            Text(item.label)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - PresetCard

private struct PresetCard: View {
    let preset: MenuBarPreset
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(preset.sample)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
        .buttonStyle(PresetCardButtonStyle(isActive: isActive, accent: accent))
    }
}

private struct PresetCardButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isActive
                    ? accent.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isActive ? accent : Color(nsColor: .separatorColor),
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
