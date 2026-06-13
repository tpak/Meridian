// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLoggerKit
import CoreModelKit
import Sparkle

@main
open class AppDelegate: NSObject, NSApplicationDelegate {
    internal lazy var panelController = PanelController(windowNibName: .panel)
    /// v4 "Daybreak" SwiftUI popover. When `useDaybreakPanel` is true the status-item click routes
    /// here instead of the legacy `panelController`; flip the flag to fall back instantly.
    internal lazy var daybreakPanelController = DaybreakPanelController()
    private let useDaybreakPanel = true
    /// v4 SwiftUI Settings window. When `useV4Settings` is true, the Daybreak footer + ⌘, open this
    /// instead of the legacy storyboard Preferences; flip the flag to fall back.
    internal lazy var settingsWindowController = SettingsWindowController()
    private let useV4Settings = true

    /// Open Settings, routing to the v4 window or the legacy Preferences per the flag.
    @objc func openSettingsRouted() {
        if useV4Settings {
            settingsWindowController.show()
        } else {
            panelController.openPreferencesWindow()
        }
    }
    private lazy var statusBarHandler: StatusItemHandler = StatusItemHandler(with: DataStore.shared())
    lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }()
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var backfillTask: Task<Void, Never>?
    private var sentinelTask: Task<Void, Never>?

    public func applicationDidFinishLaunching(_: Notification) {
        AppDefaults.initialize(with: DataStore.shared(), defaults: UserDefaults.standard)
        // Single swizzle on +controlAccentColor — covers popups,
        // segmented controls, checkboxes, sliders, focus rings.
        AccentColorSwizzler.install()
        logLaunch()
        sentinelTask = Task.detached(priority: .utility) {
            self.checkForPreviousUncleanExit()
            self.writeSentinelFile()
        }
        enableAutoUpdateByDefault()
        backfillMissingCoordinates()
        continueUsually()
        setupMemoryPressureMonitoring()
        reopenAppearanceIfRelaunchedForTeamAccent()
        showTahoeOnboardingIfNeeded()
        observeAppActivationForVisibilityRecheck()
    }

    // MARK: - Tahoe Menubar Onboarding (#125)

    /// First time Meridian runs on a machine, surface a one-shot dialog
    /// explaining that macOS Tahoe requires the user to explicitly enable
    /// third-party menubar items in Control Center. The flag is persisted
    /// so this never re-prompts. The reactive heuristic in
    /// StatusItemHandler.verifyStatusItemVisible() handles the case where
    /// the user dismissed onboarding without flipping the toggle.
    private func showTahoeOnboardingIfNeeded() {
        // Skip during XCTest runs so the modal alert never hangs the test
        // host. Tests that need to exercise this path can drive it directly
        // through the helper used here, not via the launch sequence.
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard !UserDefaults.standard.bool(forKey: UserDefaultKeys.tahoeOnboardingShown) else { return }

        // The dialog must come after the status item has actually been
        // constructed (continueUsually() materialised the lazy var) so the
        // user sees their icon — if it shows up — at the same moment.
        DispatchQueue.main.async { [weak self] in
            self?.presentTahoeOnboardingAlert()
        }
    }

    private func presentTahoeOnboardingAlert() {
        let body = "macOS Tahoe requires you to explicitly allow apps to put icons in the menu bar. "
            + "Open System Settings → Control Center, scroll to the third-party apps section, and turn on Meridian."
        let alert = NSAlert()
        alert.messageText = "One quick setup step".localized()
        alert.informativeText = body.localized()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Control Center Settings".localized())
        alert.addButton(withTitle: "I've already done this".localized())

        let response = alert.runModal()
        UserDefaults.standard.set(true, forKey: UserDefaultKeys.tahoeOnboardingShown)

        if response == .alertFirstButtonReturn {
            ControlCenterSettings.open()
        }
    }

    /// After the user visits Settings to flip the Control Center toggle,
    /// they'll return focus to Meridian (usually via the menubar icon, the
    /// dock if `appPresentation == .both`, or the global shortcut). Catch
    /// that activation and re-run the visibility heuristic so a successful
    /// fix is reflected without requiring a relaunch — and so a still-broken
    /// state re-surfaces the recovery dialog on the next session.
    private func observeAppActivationForVisibilityRecheck() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.statusBarHandler.scheduleVisibilityVerification()
        }
    }

    /// If we were just relaunched by the user picking a new accent color
    /// from Settings → Appearance and clicking Restart Now, land them
    /// back on the Appearance tab so it doesn't feel like they lost
    /// their place. The flag is set in
    /// AppearanceViewController.promptForRestart and consumed exactly
    /// once here.
    private func reopenAppearanceIfRelaunchedForTeamAccent() {
        guard UserDefaults.standard.bool(forKey: UserDefaultKeys.reopenAppearanceOnLaunch) else { return }
        UserDefaults.standard.removeObject(forKey: UserDefaultKeys.reopenAppearanceOnLaunch)
        // Brief delay so AppDelegate finishes building the panel /
        // status item before we open Settings on top.
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.openAppearanceAfterRelaunch) { [weak self] in
            self?.panelController.oneWindow?.openAppearancePane()
        }
    }

    public func applicationWillTerminate(_: Notification) {
        Logger.production("App terminating cleanly")
        sentinelTask?.cancel()
        backfillTask?.cancel()
        removeSentinelFile()
    }

    // MARK: - Lifecycle Logging

    private func logLaunch() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let store = DataStore.shared()
        let rawCount = store.timezones().count
        let decodedCount = store.timezoneObjects().count
        Logger.production("App launched v\(version)(\(build)) on macOS \(osVersion), timezones raw=\(rawCount) decoded=\(decodedCount)")
        if rawCount != decodedCount {
            Logger.production("WARN: \(rawCount - decodedCount) timezone blob(s) failed to decode — UI will show fewer rows than persisted")
        }
    }

    // MARK: - Crash Sentinel

    private var sentinelURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Meridian")
            .appendingPathComponent(".running")
    }

    private func writeSentinelFile() {
        guard let url = sentinelURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? Date().ISO8601Format().write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeSentinelFile() {
        guard let url = sentinelURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func checkForPreviousUncleanExit() {
        guard let url = sentinelURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let timestamp = (try? String(contentsOf: url, encoding: .utf8)) ?? "unknown"
        Logger.production("Previous session exited uncleanly (launched at \(timestamp))")
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memoryPressureSource?.setEventHandler { [weak self] in
            let level = self?.memoryPressureSource?.data ?? []
            if level.contains(.critical) {
                Logger.production("Memory pressure: CRITICAL")
            } else if level.contains(.warning) {
                Logger.production("Memory pressure: WARNING")
            }
        }
        memoryPressureSource?.resume()
    }

    // MARK: - Backfill Coordinates

    private func backfillMissingCoordinates() {
        let store = DataStore.shared()
        var timezones = store.timezones()
        var indicesToBackfill: [(Int, TimezoneData)] = []

        for (index, data) in timezones.enumerated() {
            guard let timezone = TimezoneData.customObject(from: data) else { continue }
            if timezone.latitude == nil || timezone.longitude == nil,
               let timezoneID = timezone.timezoneID, !timezoneID.isEmpty {
                indicesToBackfill.append((index, timezone))
            }
        }

        guard !indicesToBackfill.isEmpty else { return }

        backfillTask = Task { @MainActor in
            for (index, timezone) in indicesToBackfill {
                let components = (timezone.timezoneID ?? "").split(separator: "/")
                guard let cityComponent = components.last else { continue }
                let cityName = cityComponent.replacingOccurrences(of: "_", with: " ")
                guard let place = try? await NetworkManager.geocodeAddress(cityName) else {
                    Logger.debug("Coordinate backfill skipped for \(cityName)")
                    continue
                }
                timezone.latitude = place.coordinate.latitude
                timezone.longitude = place.coordinate.longitude
                guard let encoded = NSKeyedArchiver.secureArchive(with: timezone) else { continue }
                timezones[index] = encoded
            }
            store.setTimezones(timezones)
        }
    }

    // MARK: - Auto-Update Default

    private func enableAutoUpdateByDefault() {
        let hasSetAutoUpdate = "HasSetAutoUpdateDefault"
        if !UserDefaults.standard.bool(forKey: hasSetAutoUpdate) {
            UserDefaults.standard.set(true, forKey: hasSetAutoUpdate)
            updaterController.updater.automaticallyChecksForUpdates = true
            updaterController.updater.automaticallyDownloadsUpdates = true
        }

        // Migration: users who went through the pre-2.12.0 broken period may have
        // automaticallyDownloadsUpdates = true but automaticallyChecksForUpdates = false.
        // Sparkle requires both to be true for scheduled background checks to run,
        // so sync them once.
        let hasFixedAutoUpdateSync = "HasFixedAutoUpdateSync"
        if !UserDefaults.standard.bool(forKey: hasFixedAutoUpdateSync) {
            UserDefaults.standard.set(true, forKey: hasFixedAutoUpdateSync)
            if updaterController.updater.automaticallyDownloadsUpdates {
                updaterController.updater.automaticallyChecksForUpdates = true
            }
        }

        let checks = updaterController.updater.automaticallyChecksForUpdates
        let downloads = updaterController.updater.automaticallyDownloadsUpdates
        let interval = updaterController.updater.updateCheckInterval
        Logger.production("Sparkle autoupdate: checks=\(checks) downloads=\(downloads) interval=\(Int(interval))s")
    }

    // MARK: - Dock Menu

    public func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Quick Access")

        let toggleMenuItem = NSMenuItem(title: "Toggle Panel", action: #selector(AppDelegate.togglePanel(_:)), keyEquivalent: "")
        let openPreferences = NSMenuItem(title: "Settings", action: #selector(AppDelegate.openPreferencesWindow), keyEquivalent: ",")
        let checkForUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdates.target = updaterController
        let hideFromDockMenuItem = NSMenuItem(title: "Hide from Dock", action: #selector(AppDelegate.hideFromDock), keyEquivalent: "")

        [toggleMenuItem, openPreferences, checkForUpdates, hideFromDockMenuItem].forEach {
            $0.isEnabled = true
            menu.addItem($0)
        }

        return menu
    }

    @objc private func openPreferencesWindow() {
        panelController.openPreferencesWindow()
    }

    @objc func hideFromDock() {
        DataStore.shared().appPresentation = .menubarOnly
        NSApp.setActivationPolicy(.accessory)
    }

    func continueUsually() {
        // Check if another instance of the app is already running. If so, then stop this one.
        checkIfAppIsAlreadyOpen()

        // Force the lazy var to materialize here so the menubar item appears
        // at this specific point in the launch sequence rather than on first
        // access elsewhere.
        _ = statusBarHandler

        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])

        assignShortcut()

        setActivationPolicy()
    }

    // Should we have a dock icon or just stay in the menubar?
    private func setActivationPolicy() {
        let currentActivationPolicy = NSRunningApplication.current.activationPolicy
        let activationPolicy: NSApplication.ActivationPolicy =
            DataStore.shared().appPresentation == .menubarOnly ? .accessory : .regular

        if currentActivationPolicy != activationPolicy {
            NSApp.setActivationPolicy(activationPolicy)
        }
    }

    private func checkIfAppIsAlreadyOpen() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return
        }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)

        if apps.count > 1 {
            let currentApplication = NSRunningApplication.current
            for app in apps where app != currentApplication {
                app.terminate()
            }
        }
    }

    private func assignShortcut() {
        GlobalShortcutMonitor.shared.action = { [weak self] in
            guard let button = self?.statusBarHandler.statusItem.button else { return }
            button.state = button.state == .on ? .off : .on
            self?.togglePanel(button)
        }
        GlobalShortcutMonitor.shared.register()
    }

    @IBAction open func togglePanel(_ sender: NSButton) {
        if useDaybreakPanel, let button = sender as? NSStatusBarButton {
            daybreakPanelController.toggle(relativeTo: button)
            button.state = (daybreakPanelController.window?.isVisible == true) ? .on : .off
            return
        }
        panelController.showWindow(nil)
        panelController.setActivePanel(newValue: sender.state == .on)
        NSApp.activate(ignoringOtherApps: true)
    }

    func statusItemForPanel() -> StatusItemHandler {
        return statusBarHandler
    }

    open func setupMenubarTimer() {
        statusBarHandler.setupStatusItem()
    }

    open func invalidateMenubarTimer(_ showIcon: Bool) {
        statusBarHandler.invalidateTimer(showIcon: showIcon, isSyncing: true)
    }
}

// MARK: - Sparkle Auto-Install for Menubar Apps

// Meridian runs with LSUIElement=true, so users rarely quit it. Sparkle's
// default "silent install on quit" behavior leaves downloaded updates parked
// indefinitely. Taking control here and invoking the immediate install handler
// finishes the update by relaunching the process transparently.
extension AppDelegate: SPUUpdaterDelegate {
    public func updater(_: SPUUpdater,
                        willInstallUpdateOnQuit item: SUAppcastItem,
                        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        Logger.production("Sparkle: update \(item.versionString) ready; installing and relaunching now")
        immediateInstallHandler()
        return true
    }

    // Sparkle channels (issue #98). Stable users see only items with no
    // <sparkle:channel> tag. Opting in adds the "beta" channel — they then see
    // beta-tagged items AND default-channel items, so the GA release supersedes
    // the last beta automatically.
    public func allowedChannels(for _: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: UserDefaultKeys.betaUpdatesEnabled) ? ["beta"] : []
    }

    public func updater(_: SPUUpdater,
                        mayPerform updateCheck: SPUUpdateCheck) throws {
        Logger.production("Sparkle: checking for updates (\(describe(updateCheck)))")
    }

    public func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.production("Sparkle: found update \(item.versionString)")
    }

    public func updaterDidNotFindUpdate(_: SPUUpdater) {
        Logger.production("Sparkle: no update available")
    }

    public func updater(_: SPUUpdater, didAbortWithError error: Error) {
        Logger.production("Sparkle: update check aborted — \(error.localizedDescription)")
    }

    private func describe(_ check: SPUUpdateCheck) -> String {
        switch check {
        case .updates: return "user-initiated"
        case .updatesInBackground: return "scheduled"
        case .updateInformation: return "informational"
        @unknown default: return "unknown"
        }
    }
}
