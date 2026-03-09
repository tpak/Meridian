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

    public func applicationDidFinishLaunching(_: Notification) {
        AppDefaults.initialize(with: DataStore.shared(), defaults: UserDefaults.standard)
        continueUsually()
    }

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
