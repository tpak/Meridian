// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLocation
import CoreLoggerKit
import CoreModelKit

@main
open class AppDelegate: NSObject, NSApplicationDelegate {
    internal lazy var panelController = PanelController(windowNibName: .panel)
    private var statusBarHandler: StatusItemHandler!

    public func applicationDidFinishLaunching(_: Notification) {
        AppDefaults.initialize(with: DataStore.shared(), defaults: UserDefaults.standard)
        continueUsually()
    }

    public func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Quick Access")

        let toggleMenuItem = NSMenuItem(title: "Toggle Panel", action: #selector(AppDelegate.togglePanel(_:)), keyEquivalent: "")
        let openPreferences = NSMenuItem(title: "Settings", action: #selector(AppDelegate.openPreferencesWindow), keyEquivalent: ",")
        let hideFromDockMenuItem = NSMenuItem(title: "Hide from Dock", action: #selector(AppDelegate.hideFromDock), keyEquivalent: "")

        [toggleMenuItem, openPreferences, hideFromDockMenuItem].forEach {
            $0.isEnabled = true
            menu.addItem($0)
        }

        return menu
    }

    @objc private func openPreferencesWindow() {
        panelController.openPreferences(NSButton())
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

        // Backfill coordinates for timezone entries that lack them (needed for sunrise/sunset)
        backfillMissingCoordinates()
    }

    private func backfillMissingCoordinates() {
        let store = DataStore.shared()
        let timezones = store.timezones()

        // Collect timezone IDs that need coordinate backfill
        var idsToBackfill: [String] = []
        for data in timezones {
            guard let tz = TimezoneData.customObject(from: data),
                  tz.selectionType == .timezone,
                  tz.latitude == nil || tz.longitude == nil,
                  let timezoneID = tz.timezoneID
            else { continue }
            idsToBackfill.append(timezoneID)
        }

        guard !idsToBackfill.isEmpty else { return }

        // Geocode all in parallel, then write a single store update
        Task {
            let coordinates = await withTaskGroup(
                of: (String, CLLocationCoordinate2D)?.self
            ) { group in
                for id in idsToBackfill {
                    group.addTask { await Self.geocodeTimezone(id) }
                }
                var results: [String: CLLocationCoordinate2D] = [:]
                for await result in group {
                    if let (id, coord) = result {
                        results[id] = coord
                    }
                }
                return results
            }

            guard !coordinates.isEmpty else { return }

            await MainActor.run {
                let allTimezones = store.timezones()
                let updated: [Data] = allTimezones.compactMap { data in
                    guard let tz = TimezoneData.customObject(from: data),
                          tz.selectionType == .timezone,
                          tz.latitude == nil || tz.longitude == nil,
                          let id = tz.timezoneID,
                          let coord = coordinates[id]
                    else { return data }
                    tz.latitude = coord.latitude
                    tz.longitude = coord.longitude
                    return NSKeyedArchiver.clocker_archive(with: tz)
                }
                store.setTimezones(updated)
            }
        }
    }

    private static func geocodeTimezone(_ timezoneID: String) async -> (String, CLLocationCoordinate2D)? {
        let components = timezoneID.components(separatedBy: "/")
        guard let city = components.last else { return nil }
        let cityName = city.replacingOccurrences(of: "_", with: " ")
        do {
            let placemark = try await NetworkManager.geocodeAddress(cityName)
            guard let location = placemark.location else { return nil }
            return (timezoneID, location.coordinate)
        } catch {
            return nil
        }
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
        Logger.info("Toggle Panel called with sender state \(sender.state.rawValue)")
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
