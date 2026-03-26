// Copyright © 2015 Abhishek Banthia

import SwiftUI
import CoreLoggerKit
import Sparkle

struct AboutView: View {
    private let versionString: String = {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "Meridian"
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "N/A"
        return "\(appName) \(shortVersion)"
    }()

    @AppStorage(UserDefaultKeys.startAtLogin) private var startAtLogin = false
    private let startupManager = StartupManager()

    fileprivate static let updateIntervalValues: [TimeInterval] = [86400, 604800, 2592000]
    fileprivate static let updateIntervalLabels = ["Daily", "Weekly", "Monthly"]

    var body: some View {
        VStack(spacing: 15) {
            Text(versionString)
                .font(.custom("Avenir-Light", size: 28))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("MeridianVersion")

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)

            Text("Feedback is always welcome:".localized())
                .font(.custom("Avenir-Light", size: 15))

            linkButton(
                title: "1. Open an issue on GitHub",
                underlineRange: 3..<26,
                font: .custom("Avenir-Light", size: 15),
                accessibilityID: "MeridianPrivateFeedback"
            ) {
                openURL(AboutUsConstants.GitHubIssuesURL, logEvent: "Opened GitHub Issues",
                        metadata: ["Country": Locale.autoupdatingCurrent.region?.identifier ?? ""])
            }

            linkButton(
                title: "2. View source on GitHub",
                underlineRange: 3..<24,
                font: .custom("Avenir-Light", size: 15)
            ) {
                openURL(AboutUsConstants.GitHubURL, logEvent: "Opened GitHub",
                        metadata: ["Country": Locale.autoupdatingCurrent.region?.identifier ?? ""])
            }

            Divider()
                .padding(.horizontal, 20)

            Toggle(String(localized: "Start at Login"), isOn: $startAtLogin)
                .font(.custom("Avenir-Book", size: 13))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("StartAtLogin")
                .onChange(of: startAtLogin) { newValue in
                    startupManager.toggleLogin(newValue)
                }

            AutoUpdateToggle()

            HStack(spacing: 8) {
                Text(String(localized: "Check for Updates"))
                    .font(.custom("Avenir-Light", size: 13))
                UpdateCheckControls()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func linkButton(
        title: String,
        underlineRange: Range<Int>,
        font: Font,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            buildAttributedText(title, underlineRange: underlineRange, font: font)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .ifLet(accessibilityID) { view, id in
            view.accessibilityIdentifier(id)
        }
    }

    private func buildAttributedText(_ text: String, underlineRange: Range<Int>, font: Font) -> Text {
        let startIndex = text.index(text.startIndex, offsetBy: underlineRange.lowerBound)
        let endIndex = text.index(text.startIndex, offsetBy: min(underlineRange.upperBound, text.count))

        let before = String(text[text.startIndex..<startIndex])
        let underlined = String(text[startIndex..<endIndex])
        let after = String(text[endIndex..<text.endIndex])

        return Text(before).font(font) +
               Text(underlined).font(font).underline() +
               Text(after).font(font)
    }

    private func openURL(_ urlString: String, logEvent: String, metadata: [String: Any]) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        Logger.log(object: metadata, for: logEvent as NSString)
    }
}

private struct AutoUpdateToggle: View {
    @State private var autoUpdate: Bool

    init() {
        let updater = (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater
        _autoUpdate = State(initialValue: updater?.automaticallyDownloadsUpdates ?? true)
    }

    var body: some View {
        Toggle(String(localized: "Automatically download and install updates"), isOn: $autoUpdate)
            .font(.custom("Avenir-Book", size: 13))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("AutoUpdate")
            .onChange(of: autoUpdate) { newValue in
                guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
                let updater = appDelegate.updaterController.updater
                updater.automaticallyChecksForUpdates = newValue
                updater.automaticallyDownloadsUpdates = newValue
            }
            .onAppear {
                guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
                autoUpdate = appDelegate.updaterController.updater.automaticallyDownloadsUpdates
            }
    }
}

private struct UpdateCheckControls: View {
    @State private var selectedIndex: Int

    init() {
        let updater = (NSApplication.shared.delegate as? AppDelegate)?.updaterController.updater
        let currentInterval = updater?.updateCheckInterval ?? 604800
        let index = AboutView.updateIntervalValues.firstIndex(of: currentInterval) ?? 1
        _selectedIndex = State(initialValue: index)
    }

    var body: some View {
        Picker("", selection: $selectedIndex) {
            ForEach(0..<AboutView.updateIntervalLabels.count, id: \.self) { index in
                Text(AboutView.updateIntervalLabels[index]).tag(index)
            }
        }
        .labelsHidden()
        .frame(width: 100)
        .onChange(of: selectedIndex) { newValue in
            guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
            appDelegate.updaterController.updater.updateCheckInterval = AboutView.updateIntervalValues[newValue]
        }

        Button(String(localized: "Check Now")) {
            guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
            appDelegate.updaterController.checkForUpdates(nil)
        }
        .font(.custom("Avenir-Light", size: 12))
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
