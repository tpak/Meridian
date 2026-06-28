// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Foundation

/// Canonical project URLs surfaced from the v4 Settings → General pane.
/// Recovered from the retired legacy About stack when the v4 rollback
/// scaffolding was removed (issue #166); the legacy `AboutView` is gone,
/// so only the members still referenced by `GeneralPane` are kept.
enum AboutUsConstants {
    static let GitHubURL = "https://github.com/tpak/Meridian"
    static let GitHubIssuesURL = "https://github.com/tpak/Meridian/issues"
    // The end-user manual published to GitHub Pages (docs/manual.md).
    static let ManualURL = "https://tpak.github.io/Meridian/manual.html"
}
