// Copyright © 2026 Christopher Tirpak

@testable import Meridian
import XCTest

/// Tests for Tahoe (#125) menubar-block detection. These exercise the pure
/// threshold function `MenubarBlockDetection.isStatusItemBlocked(...)` and
/// the once-only semantics of `UserDefaultKeys.tahoeOnboardingShown` — no
/// real NSStatusItem is required.
final class MenubarBlockDetectionTests: XCTestCase {

    // MARK: - isStatusItemBlocked

    func testNilWindowWidthIsTreatedAsBlocked() {
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: nil,
                                                                 isCompactMode: false))
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: nil,
                                                                 isCompactMode: true))
    }

    func testZeroWidthIsBlockedInBothModes() {
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: 0,
                                                                 isCompactMode: false))
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: 0,
                                                                 isCompactMode: true))
    }

    func testIconModeJustBelowThresholdIsBlocked() {
        let width = MenubarBlockDetection.iconModeMinimumWidth - 1
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: width,
                                                                 isCompactMode: false))
    }

    func testIconModeAtThresholdIsNotBlocked() {
        XCTAssertFalse(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: MenubarBlockDetection.iconModeMinimumWidth,
                                                                  isCompactMode: false))
    }

    func testIconModeHealthyWidthIsNotBlocked() {
        XCTAssertFalse(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: 60,
                                                                  isCompactMode: false))
    }

    func testCompactModeJustBelowThresholdIsBlocked() {
        let width = MenubarBlockDetection.compactModeMinimumWidth - 1
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: width,
                                                                 isCompactMode: true))
    }

    func testCompactModeAtThresholdIsNotBlocked() {
        XCTAssertFalse(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: MenubarBlockDetection.compactModeMinimumWidth,
                                                                  isCompactMode: true))
    }

    func testCompactModeHealthyWidthIsNotBlocked() {
        XCTAssertFalse(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: 120,
                                                                  isCompactMode: true))
    }

    /// Compact mode threshold must be stricter than icon mode — a width that
    /// passes icon mode might still be a blocked compact item (Control Center
    /// allocates a tiny placeholder slot that's wider than a clock icon but
    /// narrower than a 2-timezone text strip).
    func testCompactThresholdIsStricterThanIconThreshold() {
        XCTAssertGreaterThan(MenubarBlockDetection.compactModeMinimumWidth,
                             MenubarBlockDetection.iconModeMinimumWidth)
    }

    func testWidthBetweenIconAndCompactThresholds() {
        let between = (MenubarBlockDetection.iconModeMinimumWidth + MenubarBlockDetection.compactModeMinimumWidth) / 2
        XCTAssertFalse(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: between,
                                                                  isCompactMode: false),
                       "Width above icon threshold should pass icon-mode check")
        XCTAssertTrue(MenubarBlockDetection.isStatusItemBlocked(buttonWindowWidth: between,
                                                                 isCompactMode: true),
                      "Same width should fail compact-mode check — compact needs more pixels")
    }

    // MARK: - Onboarding flag persistence (issue #125)

    /// The first-launch onboarding alert is gated by
    /// UserDefaultKeys.tahoeOnboardingShown. AppDefaults registers this with
    /// a default of `false` so first launch always presents the dialog;
    /// AppDelegate flips it to `true` once shown. This test exercises the
    /// AppDefaults registration and the simple read/write semantics, which
    /// together back the "show once and only once" guarantee.
    func testTahoeOnboardingShownDefaultsToFalse() {
        // Use a fixed suite name (not a per-run UUID) so the backing plist in
        // ~/Library/Preferences is reused and overwritten instead of accumulating a new
        // file every run. removePersistentDomain clears a suite's contents but does not
        // delete its plist file, so a UUID-based name leaks one stray plist per test run.
        let suiteName = "com.tpak.meridian.tests.TahoeOnboardingDefaults"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppDefaults.initialize(with: DataStore.shared(), defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: UserDefaultKeys.tahoeOnboardingShown),
                       "Fresh defaults must report false so first launch triggers onboarding")
    }

    func testTahoeOnboardingShownRoundTrips() {
        let suiteName = "com.tpak.meridian.tests.TahoeOnboardingRoundTrip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: UserDefaultKeys.tahoeOnboardingShown)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultKeys.tahoeOnboardingShown))
    }

    // MARK: - Control Center deep link

    func testControlCenterSettingsURLIsCorrect() {
        XCTAssertEqual(ControlCenterSettings.urlString,
                       "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
                       "Deep link must match the System Settings → Control Center extension URL — anything else opens the wrong pane")
    }

    func testControlCenterSettingsURLParsesAsValidURL() {
        XCTAssertEqual(ControlCenterSettings.url.absoluteString,
                       ControlCenterSettings.urlString)
    }
}
