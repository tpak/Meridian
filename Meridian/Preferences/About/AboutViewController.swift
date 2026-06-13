// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import SwiftUI

struct AboutUsConstants {
    static let GitHubURL = "https://github.com/tpak/Meridian"
    static let GitHubIssuesURL = "https://github.com/tpak/Meridian/issues"
    static let AppStoreLink = "https://github.com/tpak/Meridian"
    static let FAQsLink = "https://github.com/tpak/Meridian/wiki"
}

class AboutViewController: ParentViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
