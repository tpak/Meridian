// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit
import Sparkle

@main
open class AppDelegate: NSObject, NSApplicationDelegate {
    internal lazy var panelController = PanelController(windowNibName: .panel)
    private var statusBarHandler: StatusItemHandler!
    lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }()
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var backfillTask: Task<Void, Never>?
    private var sentinelTask: Task<Void, Never>?

    public func applicationDidFinishLaunching(_: Notification) {
        AppDefaults.initialize(with: DataStore.shared(), defaults: UserDefaults.standard)
        logLaunch()
        sentinelTask = Task.detached(priority: .utility) {
            self.checkForPreviousUncleanExit()
            self.writeSentinelFile()
        }
        enableAutoUpdateByDefault()
        backfillMissingCoordinates()
        continueUsually()
        setupMemoryPressureMonitoring()
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
        let tzCount = DataStore.shared().timezones().count
        Logger.production("App launched v\(version)(\(build)) on macOS \(osVersion), \(tzCount) timezones")
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
                guard let placemark = try? await NetworkManager.geocodeAddress(cityName),
                      let location = placemark.location else {
                    Logger.debug("Coordinate backfill skipped for \(cityName)")
                    continue
                }
                timezone.latitude = location.coordinate.latitude
                timezone.longitude = location.coordinate.longitude
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
        UserDefaults.standard.set(0, forKey: UserDefaultKeys.appDisplayOptions)
        NSApp.setActivationPolicy(.accessory)
    }

    func continueUsually() {
        // Check if another instance of the app is already running. If so, then stop this one.
        checkIfAppIsAlreadyOpen()

        // Install the menubar item!
        statusBarHandler = StatusItemHandler(with: DataStore.shared())

        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])

        assignShortcut()

        setActivationPolicy()
    }

    // Should we have a dock icon or just stay in the menubar?
    private func setActivationPolicy() {
        let defaults = UserDefaults.standard

        let currentActivationPolicy = NSRunningApplication.current.activationPolicy
        let activationPolicy: NSApplication.ActivationPolicy = defaults.integer(forKey: UserDefaultKeys.appDisplayOptions) == 0 ? .accessory : .regular

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
