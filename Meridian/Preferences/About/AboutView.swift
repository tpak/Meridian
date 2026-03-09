// Copyright © 2015 Abhishek Banthia

import SwiftUI
import CoreLoggerKit

struct AboutView: View {
    private let versionString: String = {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "Meridian"
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "N/A"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "N/A"
        return "\(appName) \(shortVersion) (\(buildVersion))"
    }()

    var body: some View {
        VStack(spacing: 15) {
            Text(versionString)
                .font(.custom("Avenir-Light", size: 28))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ClockerVersion")

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)

            Text("Feedback is always welcome:".localized())
                .font(.custom("Avenir-Light", size: 15))

            linkButton(
                title: "1. Open an issue on GitHub",
                underlineRange: 3..<26,
                font: .custom("Avenir-Light", size: 15),
                accessibilityID: "ClockerPrivateFeedback"
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
