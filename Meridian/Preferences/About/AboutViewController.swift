// Copyright © 2015 Abhishek Banthia

import Cocoa
import SwiftUI

struct AboutUsConstants {
    static let GitHubURL = "https://github.com/tpak/meridian"
    static let GitHubIssuesURL = "https://github.com/tpak/meridian/issues"
    static let AppStoreLink = "https://github.com/tpak/meridian"
    static let FAQsLink = "https://github.com/tpak/meridian/wiki"
    static let OriginalProjectURL = "https://github.com/n0shake/Clocker"
    static let CrowdInLocalizationLink = "https://crwd.in/clocker"
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
