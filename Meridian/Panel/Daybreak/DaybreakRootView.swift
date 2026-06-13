// Copyright © 2026 Chris Tirpak
//
// DaybreakRootView — the SwiftUI root hosted inside the menu-bar panel. Composes the hero, the city
// cards, the scrubber, and the footer, and draws the popover chrome (378px body, 18px radius,
// hairline border, soft shadow, top notch). Owns the inline time-edit state shared by the hero and
// rows, and resolves light/dark from the user's Theme preference (README §1 surfaces).

import SwiftUI

struct DaybreakRootView: View {
    @ObservedObject var viewModel: DaybreakViewModel
    var isFloating: Bool = false
    var onOpenSettings: () -> Void = {}
    var onTogglePin: () -> Void = {}

    @Environment(\.colorScheme) private var systemScheme
    @State private var editingID: String?
    @State private var editText: String = ""
    @State private var paletteTick = 0

    private var palette: DaybreakPalette {
        _ = paletteTick // re-resolve when prefs change
        let effective: ColorScheme
        switch DataStore.shared().theme {
        case .light: effective = .light
        case .dark: effective = .dark
        default: effective = systemScheme
        }
        return DaybreakPalette.resolve(effective)
    }

    private var themeOverride: ColorScheme? {
        switch DataStore.shared().theme {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    var body: some View {
        let snapshot = viewModel.snapshot
        VStack(spacing: 0) {
            DaybreakHeroView(
                hero: snapshot.hero,
                palette: palette,
                isEditing: editingID == "hero",
                editText: $editText,
                onBeginEdit: { beginEdit(id: "hero", time: snapshot.hero.time, period: snapshot.hero.period) },
                onCommit: { commitEdit() },
                onCancel: { cancelEdit() }
            )

            cityCards(snapshot)

            DaybreakScrubber(
                data: snapshot.scrubber,
                palette: palette,
                onScrubFraction: { viewModel.setOffsetFromFraction($0) },
                onNudge: { viewModel.nudge(forward: $0) },
                onReset: { viewModel.reset() }
            )

            footer(snapshot)
        }
        .frame(width: 378)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.hairline, lineWidth: 1))
        .overlay(alignment: .topTrailing) { notch(snapshot) }
        .shadow(color: palette.shadowColor, radius: palette.shadowRadius, y: palette.shadowY)
        .padding(.horizontal, 40)
        .padding(.top, 14)
        .padding(.bottom, 44)
        .preferredColorScheme(themeOverride)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            paletteTick &+= 1
        }
    }

    @ViewBuilder private func cityCards(_ snapshot: DaybreakSnapshot) -> some View {
        if snapshot.cities.isEmpty {
            Text("Add places in Settings to see them here.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 22)
                .padding(.horizontal, 13)
        } else {
            VStack(spacing: 8) {
                ForEach(snapshot.cities) { city in
                    DaybreakCityRow(
                        city: city,
                        palette: palette,
                        isEditing: editingID == city.id,
                        editText: $editText,
                        onBeginEdit: { beginEdit(id: city.id, time: city.time, period: city.period) },
                        onCommit: { commitEdit() },
                        onCancel: { cancelEdit() }
                    )
                }
            }
            .padding(EdgeInsets(top: 13, leading: 13, bottom: 4, trailing: 13))
        }
    }

    private func footer(_ snapshot: DaybreakSnapshot) -> some View {
        HStack {
            Button(action: onOpenSettings) {
                Text("Settings").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.foot)
            }
            .buttonStyle(.plain)

            Spacer()
            Text(snapshot.versionText)
                .font(.system(size: 11))
                .foregroundStyle(palette.footVersion)
            Spacer()

            Button(action: onTogglePin) {
                Text(isFloating ? "Unpin ▼" : "Pin ▲")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.foot)
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 10, leading: 18, bottom: 14, trailing: 18))
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func notch(_ snapshot: DaybreakSnapshot) -> some View {
        UpTriangle()
            .fill(DaybreakSky.notchColor(for: snapshot.hero.phase))
            .frame(width: 18, height: 9)
            .padding(.trailing, 51)
            .offset(y: -8)
    }

    // MARK: Inline edit

    private func beginEdit(id: String, time: String, period: String) {
        editText = period.isEmpty ? time : "\(time) \(period)"
        editingID = id
    }

    private func commitEdit() {
        if let id = editingID {
            viewModel.commitEditedTime(cityID: id, text: editText)
        }
        editingID = nil
    }

    private func cancelEdit() {
        editingID = nil
    }
}

/// Upward-pointing triangle for the popover notch.
private struct UpTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
