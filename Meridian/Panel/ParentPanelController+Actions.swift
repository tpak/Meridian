// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

// MARK: - Actions

extension ParentPanelController {
    @objc func openPreferencesWindow() {
        oneWindow?.openGeneralPane()
    }

    /// Sender-taking overload reached via the responder chain. The empty-
    /// state "+" button in Panel.xib (AddTableViewCell) sends
    /// `openPreferences:` to the First Responder. Without this method, the
    /// selector dispatches nowhere and the button is silently dead — which
    /// is the only way to add the first timezone after a fresh install or
    /// a full remove, so the app was unusable from an empty state.
    @objc func openPreferences(_: Any?) {
        openPreferencesWindow()
    }

    func minutes(from date: Date, other: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: other).minute ?? 0
    }

    @objc dynamic func terminateMeridian() {
        NSApplication.shared.terminate(nil)
    }

    @objc func copyFirstTimezoneToClipboard() {
        guard mainTableView.numberOfRows > 0,
              let cellView = mainTableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? TimezoneCellView else {
            return
        }

        let clipboardCopy = "\(cellView.customName.stringValue) - \(cellView.time.stringValue)"
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(clipboardCopy, forType: .string)
        window?.contentView?.makeToast("Copied to Clipboard".localized())
    }

    @objc func copyAllTimezonesToClipboard() {
        let timezones = dataStore.timezoneObjects()
        guard !timezones.isEmpty else { return }

        let parts = timezones.map { timezone -> String in
            let ops = TimezoneDataOperations(with: timezone, store: dataStore)
            let timeStr = ops.time(with: futureSliderValue)
            let label = timezone.formattedTimezoneLabel()
            return "\(timeStr) \(label)"
        }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(parts.joined(separator: " / "), forType: .string)
        window?.contentView?.makeToast("Copied to Clipboard".localized())
    }

    @objc func reportIssue() {
        guard let url = URL(string: AboutUsConstants.GitHubIssuesURL) else { return }
        NSWorkspace.shared.open(url)

        if let countryCode = Locale.autoupdatingCurrent.region?.identifier {
            let custom: [String: Any] = ["Country": countryCode]
            Logger.debug("Report Issue Opened: \(custom)")
        }
    }

    @objc func rate() {
        guard let sourceURL = URL(string: AboutUsConstants.AppStoreLink) else { return }

        NSWorkspace.shared.open(sourceURL)
    }

    @objc func openFAQs() {
        guard let sourceURL = URL(string: AboutUsConstants.FAQsLink) else { return }

        NSWorkspace.shared.open(sourceURL)
    }
}
