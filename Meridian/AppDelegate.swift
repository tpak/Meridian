// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit
import Sparkle

@main
open class AppDelegate: NSObject, NSApplicationDelegate {
    internal lazy var panelController = PanelController(windowNibName: .panel)
    private var statusBarHandler: StatusItemHandler!
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
        guard !UserDefaults.standard.bool(forKey: hasSetAutoUpdate) else { return }
        UserDefaults.standard.set(true, forKey: hasSetAutoUpdate)
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.automaticallyDownloadsUpdates = true
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
