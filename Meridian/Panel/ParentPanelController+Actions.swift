// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

// MARK: - Actions

extension ParentPanelController {
    @objc func openPreferencesWindow() {
        oneWindow?.openGeneralPane()
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
