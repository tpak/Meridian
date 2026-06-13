// Copyright © 2026 Chris Tirpak
//
// SettingsRootView — the v4 Settings window root: a Ventura-style NavigationSplitView with a
// sidebar (Cities · Menu Bar · Appearance · Time Travel · General) and a detail pane. The accent
// is the user's TeamAccent livery. Each detail pane binds directly to @AppStorage / DataStore;
// only Cities needs the stateful CityListModel.

import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case cities, menuBar, appearance, timeTravel, general
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cities: return "Cities"
        case .menuBar: return "Menu Bar"
        case .appearance: return "Appearance"
        case .timeTravel: return "Time Travel"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .cities: return "globe"
        case .menuBar: return "menubar.rectangle"
        case .appearance: return "paintbrush"
        case .timeTravel: return "clock.arrow.2.circlepath"
        case .general: return "gearshape"
        }
    }
}

struct SettingsRootView: View {
    @StateObject private var cityModel = CityListModel()
    @State private var selection: SettingsPane = .cities
    @State private var accentTick = 0

    private var accent: Color {
        _ = accentTick
        return Color(nsColor: DataStore.shared().teamAccent.accentColor)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.title).font(.system(size: 13))
                    } icon: {
                        Image(systemName: pane.symbol)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(198)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("Meridian \(shortVersion)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .tint(accent)
        .frame(minWidth: 748, minHeight: 744)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorDidChange)) { _ in
            accentTick &+= 1
        }
    }

    @ViewBuilder private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selection {
                case .cities: CitiesPane(model: cityModel, accent: accent)
                case .menuBar: MenuBarPane(accent: accent)
                case .appearance: AppearancePane(accent: accent)
                case .timeTravel: TimeTravelPane(accent: accent)
                case .general: GeneralPane(accent: accent)
                }
            }
            // Top inset clears the transparent, full-size-content-view titlebar where the window's
            // "Settings" title is drawn — otherwise the first pane header (e.g. "Cities") collides
            // with it, and on overscroll the two visibly swish together.
            .padding(EdgeInsets(top: 44, leading: 28, bottom: 28, trailing: 28))
        }
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0"
    }
}
