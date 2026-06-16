// Copyright © 2026 Chris Tirpak
//
// GeneralPane — the v4 Settings "General" detail pane. Login, updates, beta &
// debug toggles, update-frequency segment, settings backup, and an About block.
// Reuses the exact Sparkle / SettingsManager / StartupManager / Logger logic
// proven in Preferences/About/AboutView.swift so behavior stays identical.

import SwiftUI
import CoreLoggerKit
import Sparkle

struct GeneralPane: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header()

            VStack(alignment: .leading, spacing: 14) {
                StartAtLoginRow(accent: accent)
                AutoUpdateRow(accent: accent)
                BetaRow(accent: accent)
                DebugRow(accent: accent)
            }

            UpdateFrequencyRow(accent: accent)
                .padding(.vertical, 18)

            Divider().padding(.bottom, 18)

            BackupButtons()
                .frame(maxWidth: .infinity, alignment: .center)

            Divider().padding(.top, 18).padding(.bottom, 18)

            AboutBlock()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Header

private struct Header: View {
    var body: some View {
        // Spec: General heading has no subtitle paragraph, just the 18pt bottom margin.
        Text(String(localized: "General"))
            .font(.system(size: 20, weight: .bold))
            .padding(.bottom, 18)
    }
}

// MARK: - Shared form row

// A 150pt right-aligned label column, the control, then an optional trailing note.
private struct FormRow<Control: View>: View {
    let label: String
    var note: String = ""
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)

            control()

            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ToggleRow: View {
    let label: String
    var note: String = ""
    let accent: Color
    @Binding var isOn: Bool

    var body: some View {
        FormRow(label: label, note: note) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(AccentSwitchToggleStyle(accent: accent))
        }
    }
}

// MARK: - Toggle rows

private struct StartAtLoginRow: View {
    let accent: Color
    @AppStorage(UserDefaultKeys.startAtLogin) private var startAtLogin = false
    private let startupManager = StartupManager()

    var body: some View {
        ToggleRow(label: String(localized: "Start at login"), accent: accent, isOn: $startAtLogin)
            .onChange(of: startAtLogin) { _, newValue in
                startupManager.toggleLogin(newValue)
            }
            .accessibilityIdentifier("StartAtLogin")
    }
}

// Drives Sparkle's automatic download/install flags directly — there is no
// @AppStorage backing for these (Sparkle owns the keys), so we mirror
// AboutView's pattern of reading/writing through the updater.
private struct AutoUpdateRow: View {
    let accent: Color
    @State private var autoUpdate: Bool

    init(accent: Color) {
        self.accent = accent
        let updater = (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater
        _autoUpdate = State(initialValue: updater?.automaticallyDownloadsUpdates ?? true)
    }

    var body: some View {
        ToggleRow(label: String(localized: "Auto-install updates"), accent: accent, isOn: $autoUpdate)
            .accessibilityIdentifier("AutoUpdate")
            .onChange(of: autoUpdate) { _, newValue in
                // Auto-install controls ONLY auto-download; whether Sparkle *checks* on a schedule is
                // owned by UpdateFrequencyRow. Writing automaticallyChecksForUpdates here would
                // silently disable scheduled checks while the frequency segment still showed Daily.
                Self.updater?.automaticallyDownloadsUpdates = newValue
            }
            .onAppear {
                if let updater = Self.updater {
                    autoUpdate = updater.automaticallyDownloadsUpdates
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                // Reflect a settings import without leaving the pane.
                if let updater = Self.updater {
                    autoUpdate = updater.automaticallyDownloadsUpdates
                }
            }
    }

    private static var updater: SPUUpdater? {
        (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater
    }
}

// Beta channel opt-in (issue #98). Flipping on triggers an immediate background
// check so a pending beta surfaces without waiting for the next poll.
private struct BetaRow: View {
    let accent: Color
    @AppStorage(UserDefaultKeys.betaUpdatesEnabled) private var receiveBetas = false

    var body: some View {
        ToggleRow(label: String(localized: "Receive beta releases"), note: String(localized: "May have bugs"), accent: accent, isOn: $receiveBetas)
            .accessibilityIdentifier("ReceiveBetaReleases")
            .onChange(of: receiveBetas) { _, _ in
                guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
                appDelegate.updaterController.updater.checkForUpdateInformation()
            }
    }
}

private struct DebugRow: View {
    let accent: Color
    @AppStorage(UserDefaultKeys.debugLoggingEnabled) private var debugLogging = false

    var body: some View {
        ToggleRow(label: String(localized: "Debug logging"), accent: accent, isOn: $debugLogging)
            .accessibilityIdentifier("DebugLogging")
    }
}

// MARK: - Update frequency

private struct UpdateFrequencyRow: View {
    let accent: Color

    // Sparkle stores the interval in seconds. "Manually" disables scheduled
    // checks; Daily / Weekly map to the standard intervals AboutView uses.
    private static let intervals: [TimeInterval] = [0, 86400, 604800]
    private static let labels = [String(localized: "Manually"), String(localized: "Daily"), String(localized: "Weekly")]

    @State private var selectedIndex: Int

    init(accent: Color) {
        self.accent = accent
        let updater = (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater
        let interval = updater?.updateCheckInterval ?? 604800
        let index = Self.intervals.firstIndex(of: interval) ?? 2
        _selectedIndex = State(initialValue: index)
    }

    var body: some View {
        // Two rows: the frequency segment, then "Check Now" on its own line aligned under the
        // segment (empty label column) instead of being pushed out to the right edge (UAT feedback).
        VStack(alignment: .leading, spacing: 10) {
            FormRow(label: String(localized: "Check for updates")) {
                Picker("", selection: $selectedIndex) {
                    ForEach(0..<Self.labels.count, id: \.self) { index in
                        Text(Self.labels[index]).tag(index)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .tint(accent)
                .fixedSize()
                .onChange(of: selectedIndex) { _, newValue in
                    guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
                    let updater = appDelegate.updaterController.updater
                    let interval = Self.intervals[newValue]
                    // Interval 0 = manual: stop scheduling checks entirely.
                    updater.automaticallyChecksForUpdates = interval > 0
                    if interval > 0 {
                        updater.updateCheckInterval = interval
                    }
                }
                .onAppear { syncSelection() }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    syncSelection() // reflect a settings import / external change
                }
            }

            FormRow(label: "") {
                Button(String(localized: "Check Now")) {
                    guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
                    appDelegate.updaterController.checkForUpdates(nil)
                }
                .font(.system(size: 12))
                .buttonStyle(ShadedButtonStyle())
            }
        }
    }

    private static var updater: SPUUpdater? {
        (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater
    }

    private func syncSelection() {
        guard let updater = Self.updater else { return }
        // "Manually" whenever scheduled checks are off, regardless of the stored interval.
        guard updater.automaticallyChecksForUpdates else { selectedIndex = 0; return }
        selectedIndex = Self.intervals.firstIndex(of: updater.updateCheckInterval) ?? 2
    }
}

// MARK: - Settings backup / log

private struct BackupButtons: View {
    @AppStorage(UserDefaultKeys.debugLoggingEnabled) private var debugLogging = false

    var body: some View {
        HStack(spacing: 10) {
            Button(String(localized: "Export Settings…")) { SettingsManager.exportSettings() }
                .accessibilityIdentifier("ExportSettings")
            Button(String(localized: "Import Settings…")) { SettingsManager.importSettings() }
                .accessibilityIdentifier("ImportSettings")
            Button(String(localized: "Export Log")) { exportLog() }
                .disabled(!debugLogging)
                .accessibilityIdentifier("ExportLog")
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(ShadedButtonStyle())
    }

    private func exportLog() {
        // UUID in filename prevents collisions across exports and reduces
        // predictability. Restrict to user-only read/write on shared systems.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meridian-log-\(UUID().uuidString).txt")
        do {
            try Logger.exportLog(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: url.path)
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        } catch {
            Logger.production("Failed to export log: \(error.localizedDescription)")
        }
    }
}

// MARK: - About block

private let lastCheckedFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

private struct AboutBlock: View {
    @State private var lastCheckDate: Date?

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0"
        return "Meridian \(short)"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(versionString)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityIdentifier("MeridianVersion")

            Text(lastCheckedText)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                LinkText(String(localized: "Open an issue")) {
                    open(AboutUsConstants.GitHubIssuesURL, log: "Opened GitHub Issues")
                }
                .accessibilityIdentifier("MeridianPrivateFeedback")

                LinkText(String(localized: "View source")) {
                    open(AboutUsConstants.GitHubURL, log: "Opened GitHub")
                }

                // Tahoe (#125) recovery link — escape hatch for users who lost
                // the menu bar icon.
                LinkText(String(localized: "Can't see it in your menu bar?")) {
                    ControlCenterSettings.open()
                    Logger.debug("Opened Control Center Settings from General tab")
                }
                .accessibilityIdentifier("MenubarTroubleshooting")
            }
        }
        .onAppear { refreshLastChecked() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshLastChecked()
        }
    }

    private var lastCheckedText: String {
        guard let date = lastCheckDate else { return String(localized: "Last checked: Never") }
        return String(localized: "Last checked \(lastCheckedFormatter.string(from: date))")
    }

    private func refreshLastChecked() {
        lastCheckDate = (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater.lastUpdateCheckDate
    }

    private func open(_ urlString: String, log: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        Logger.debug(log)
    }
}

private struct LinkText: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        // Shaded so it reads as a button on the dark canvas rather than blending in like the old
        // accent-coloured plain text link (UAT feedback).
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
        }
        .buttonStyle(ShadedButtonStyle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// A clearly-shaded button background (fill + hairline border) so command buttons read as buttons
// against the settings window's dark canvas — the system `.bordered` style renders nearly invisibly
// here (UAT feedback). Adapts to light/dark via `Color.primary` and dims when disabled.
private struct ShadedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ShadedButtonLabel(configuration: configuration)
    }

    private struct ShadedButtonLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}
