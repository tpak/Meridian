// Copyright © 2026 Chris Tirpak
//
// CitiesPane — v4 Settings → Cities detail pane. Manages the tracked timezone list: a Home /
// Currently-in locations card, a search-to-add field, a sort control, and the reorderable city
// list with per-row favourite star, color dot, inline label, and remove. Mirrors the design
// handoff (right-aligned ~150px label column, card-on-window form rows, F1-livery accent tinting).

import SwiftUI

struct CityLocationOption: Identifiable {
    let id: String
    let label: String
}

struct CitiesPane: View {
    @ObservedObject var model: CityListModel
    let accent: Color

    @AppStorage("com.tpak.meridian.v4.pinCurrentToTop") private var pinCurrentToTop = true
    static let locationControlWidth: CGFloat = 200

    @State private var query = ""
    @State private var searchResults: [String] = []
    @State private var colorPickFor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            locationsCard
            searchField
            sortControl
            cityList
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cities")
                .font(.system(size: 20, weight: .bold))
            Text("Track timezones, star the ones for your menu bar, set a color and a short label.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Locations card

private extension CitiesPane {
    var locationsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            homeRow
            currentRow
            pinRow
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(cardBackground)
        .padding(.bottom, 14)
    }

    var homeRow: some View {
        FormRow(label: "Home") {
            // Custom-styled Menu (not a native Picker, which hugs its content and won't honor a
            // fixed width) so it's the exact same box as "Currently in" and they align.
            Menu {
                ForEach(uniqueLocations) { option in
                    Button(option.label) { model.setHome(timezoneID: option.id) }
                }
            } label: {
                locationBox(homeLabel, showsChevron: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Text("Always marked with the house")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    var currentRow: some View {
        FormRow(label: "Currently in") {
            locationBox(currentLocationLabel, showsChevron: false)
            Text("Auto-detected when you travel")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    /// Shared 200×26 control box used by both Home and Currently-in so they align exactly.
    func locationBox(_ text: String, showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 12.5)).lineLimit(1).foregroundStyle(.primary)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .frame(width: Self.locationControlWidth, height: 26, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }

    var homeLabel: String {
        uniqueLocations.first(where: { $0.id == model.effectiveHomeID })?.label ?? "—"
    }

    /// Unique options for the Home picker — display the friendly label, and avoid duplicate tags
    /// when the list has two rows sharing a timezone.
    var uniqueLocations: [CityLocationOption] {
        var seen = Set<String>()
        var result: [CityLocationOption] = []
        for row in model.rows where !seen.contains(row.timezoneID) {
            seen.insert(row.timezoneID)
            result.append(CityLocationOption(id: row.timezoneID, label: row.label))
        }
        return result
    }

    var pinRow: some View {
        FormRow(label: "Pin to top") {
            Toggle("", isOn: $pinCurrentToTop)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .onChange(of: pinCurrentToTop) { _, _ in model.reload() }
            Text("Show your current timezone first in Meridian")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    var homeBinding: Binding<String> {
        Binding(
            // effectiveHomeID matches the row's isHome computation, so the picker selection and the
            // ⌂ badge always agree (even before a home is explicitly persisted).
            get: { model.effectiveHomeID },
            set: { model.setHome(timezoneID: $0) }
        )
    }

    var currentLocationLabel: String {
        model.rows.first(where: { $0.isCurrent })?.label ?? "—"
    }
}

// MARK: - Search to add

private extension CitiesPane {
    var searchField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Add a city or timezone…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onChange(of: query) { _, newValue in
                        searchResults = model.searchTimezones(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if !searchResults.isEmpty {
                searchResultsList
            }
        }
        .padding(.bottom, 14)
    }

    var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(searchResults, id: \.self) { identifier in
                Button {
                    addResult(identifier)
                } label: {
                    Text(identifier.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 12.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .padding(.top, 4)
    }

    func addResult(_ identifier: String) {
        model.addTimezone(identifier: identifier)
        query = ""
        searchResults = []
    }
}

// MARK: - Sort control

private extension CitiesPane {
    var sortControl: some View {
        HStack(spacing: 8) {
            Text("Sort")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Picker("", selection: $model.sort) {
                ForEach(CityListModel.SortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240)
            Spacer()
        }
        .padding(.bottom, 12)
    }
}

// MARK: - City list

private extension CitiesPane {
    var cityList: some View {
        // Plain VStack (not a List): rows take their natural height so they never clip, and the
        // outer Settings scroll view scrolls only when the whole pane exceeds the window — so ~5-6
        // cities show before a scrollbar appears. (Drag-reorder, which needs a List, is inactive;
        // Sort handles ordering.)
        VStack(spacing: 8) {
            ForEach(model.rows) { row in
                CityRowView(
                    row: row,
                    accent: accent,
                    isPicking: colorPickFor == row.id,
                    onToggleFavourite: { model.toggleFavourite(row.id) },
                    onTogglePicker: { togglePicker(row.id) },
                    onPickColor: { hex in
                        model.setColor(row.id, hex: hex)
                        colorPickFor = nil
                    },
                    onCommitLabel: { text in model.setLabel(row.id, text) },
                    onRemove: { model.remove(row.id) }
                )
            }
        }
    }

    func togglePicker(_ id: String) {
        colorPickFor = (colorPickFor == id) ? nil : id
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Form row

/// The Locations-card form row: a right-aligned 86px label column (spec uses a tighter column
/// inside the card than the full-pane 150px rows), then trailing controls.
private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
    }
}

// MARK: - City row

private struct CityRowView: View {
    let row: SettingsCityRow
    let accent: Color
    let isPicking: Bool
    let onToggleFavourite: () -> Void
    let onTogglePicker: () -> Void
    let onPickColor: (String) -> Void
    let onCommitLabel: (String) -> Void
    let onRemove: () -> Void

    @State private var labelText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isPicking { palette }
        }
        .padding(.vertical, 4)
        .background(rowBackground)
        .onAppear { labelText = row.label }
        .onChange(of: row.label) { _, newValue in labelText = newValue }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            favouriteButton
            colorDotButton
            details
            labelField
            removeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var favouriteButton: some View {
        Button(action: onToggleFavourite) {
            Image(systemName: row.isFavourite ? "star.fill" : "star")
                .font(.system(size: 14))
                .foregroundStyle(row.isFavourite ? accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Show in menu bar")
    }

    private var colorDotButton: some View {
        Button(action: onTogglePicker) {
            Circle()
                .fill(CityColorStore.color(for: row.id))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Set color")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(row.region)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                // One badge per row: "Here" for the current location, "⌂ Home" only when home is
                // elsewhere (avoids a redundant double badge that squeezed the name).
                if row.isCurrent { hereBadge } else if row.isHome { homeBadge }
            }
            Text("\(row.time) · \(row.offset)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var homeBadge: some View {
        Text("⌂ Home")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    private var hereBadge: some View {
        Text("Here")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(accent))
    }

    private var labelField: some View {
        TextField("Label", text: $labelText, onCommit: { onCommitLabel(labelText) })
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .frame(width: 92)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    @ViewBuilder private var removeButton: some View {
        if row.isCurrent {
            // Only the auto-detected current-location row is non-removable; everything else
            // (including a duplicate or a home-while-traveling row) can be removed.
            Color.clear.frame(width: 20, height: 20)
        } else {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
    }

    private var palette: some View {
        HStack(spacing: 8) {
            ForEach(CityColorStore.palette, id: \.self) { hex in
                Button {
                    onPickColor(hex)
                } label: {
                    Circle()
                        .fill(swatchColor(hex))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(
                                hex.caseInsensitiveCompare(row.colorHex) == .orderedSame
                                    ? accent : Color.primary.opacity(0.1),
                                lineWidth: hex.caseInsensitiveCompare(row.colorHex) == .orderedSame ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 0, leading: 53, bottom: 12, trailing: 14))
    }

    private func swatchColor(_ hex: String) -> Color {
        if let nsColor = CityColorStore.nsColor(fromHex: hex) {
            return Color(nsColor: nsColor)
        }
        return .gray
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
