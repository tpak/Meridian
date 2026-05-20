// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

class CenteredTabViewController: NSTabViewController {
    /// Posted after `tabView(_:didSelect:)` so the window controller can
    /// refresh the custom toolbar item views' selection state.
    static let didChangeSelectionNotification = Notification.Name("com.tpak.meridian.settingsTabSelectionDidChange")

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup localized tab labels
        tabViewItems.forEach { item in
            if let identifier = item.identifier as? String {
                item.label = NSLocalizedString(identifier, comment: "Tab View Item Label for \(identifier)")
            }
        }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        NotificationCenter.default.post(name: Self.didChangeSelectionNotification, object: self)
    }
}

class OneWindowController: NSWindowController {
    /// Custom views we install into each tab NSToolbarItem so AppKit
    /// can't tint the selected tab's label with the team accent (Tahoe
    /// regression — see SettingsTabToolbarItemView for the full story).
    private var customTabItemViews: [String: SettingsTabToolbarItemView] = [:]

    override func windowDidLoad() {
        super.windowDidLoad()
        setup()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshToolbarForAccentChange),
            name: .accentColorDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshTabSelectionState),
            name: CenteredTabViewController.didChangeSelectionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        setupWindow()
        installCustomTabItemViews()
        setupToolbarImages()
    }

    private func setupWindow() {
        window?.titlebarAppearsTransparent = true
        window?.backgroundColor = NSColor.windowBackgroundColor
        window?.identifier = NSUserInterfaceItemIdentifier("Preferences")
        window?.center()
    }

    private static let identifierToSymbol: [String: String] = [
        "Preferences Tab": "gearshape",
        "Appearance Tab": "paintbrush",
        "About Tab": "info.circle"
    ]

    /// Why this is more involved than just `NSImage(systemSymbolName:)`:
    ///
    /// The tint applied by AppKit for the SELECTED tab in
    /// `NSTabViewController` toolbar style does NOT go through
    /// `NSColor.controlAccentColor`. The swizzle in DataStore.swift
    /// covers controlAccentColor — verified by
    /// `testSwizzleMakesControlAccentColorReturnTeamAccent` — but the
    /// toolbar-tab tint is applied by a private AppKit code path that
    /// bypasses it entirely. That's why the toolbar tabs stayed
    /// Aston Martin green even after multiple cache-invalidation
    /// attempts.
    ///
    /// The fix: bake the team color into the SF Symbol itself with
    /// `NSImage.SymbolConfiguration(paletteColors:)`. A palette
    /// configuration is rendered into the image's bitmap when AppKit
    /// resolves the symbol, so the resulting NSImage already carries
    /// the team color. AppKit's selection tinting still applies
    /// (alpha/saturation differences between selected and unselected
    /// tabs), but the BASE color is the team color regardless.
    ///
    /// Updates both layers:
    ///   - `tabViewItem.image` — used when AppKit rebuilds the toolbar.
    ///   - `window.toolbar.items[].image` — the live rendered items.
    /// nil-then-set on the toolbar items defeats AppKit's
    /// image-identity short-circuit so the new tint actually paints.
    private func setupToolbarImages() {
        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        let teamColor = DataStore.shared().teamAccent.accentColor
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [teamColor])

        func tintedSymbol(_ name: String) -> NSImage? {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            return base.withSymbolConfiguration(paletteConfig)
        }

        // Model layer.
        tabViewController.tabViewItems.forEach { tabViewItem in
            let identity = (tabViewItem.identifier as? String) ?? ""
            if let symbol = Self.identifierToSymbol[identity] {
                tabViewItem.image = tintedSymbol(symbol)
            }
        }

        // Rendering layer.
        if let toolbar = window?.toolbar {
            for item in toolbar.items {
                if let symbol = Self.identifierToSymbol[item.itemIdentifier.rawValue] {
                    item.image = nil
                    item.image = tintedSymbol(symbol)
                }
            }
        }

        // Push the freshly-tinted icon into our custom item views so the
        // team color change is reflected in the live UI without waiting
        // for the next view rebuild.
        for (identity, view) in customTabItemViews {
            if let symbol = Self.identifierToSymbol[identity] {
                view.setImage(tintedSymbol(symbol))
            }
        }
    }

    @objc private func refreshToolbarForAccentChange() {
        let team = DataStore.shared().teamAccent.displayName
        Logger.production("[Accent] refreshToolbar fired: team=\(team)")
        setupToolbarImages()
    }

    /// Install a `SettingsTabToolbarItemView` as `item.view` for each
    /// tab toolbar item. Routing clicks back through
    /// `selectedTabViewItemIndex` preserves the standard tab semantics
    /// while letting us render the icon, label, and selection state
    /// with explicit colors AppKit can't override.
    private func installCustomTabItemViews() {
        guard let toolbar = window?.toolbar,
              let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        let teamColor = DataStore.shared().teamAccent.accentColor
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [teamColor])

        customTabItemViews.removeAll(keepingCapacity: true)

        for item in toolbar.items {
            let identity = item.itemIdentifier.rawValue
            guard let symbolName = Self.identifierToSymbol[identity] else { continue }

            let tabIndex = tabViewController.tabViewItems.firstIndex {
                ($0.identifier as? String) == identity
            }
            guard let tabIndex else { continue }

            let title = tabViewController.tabViewItems[tabIndex].label
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(paletteConfig)

            let view = SettingsTabToolbarItemView(image: image, title: title)
            view.isSelected = (tabViewController.selectedTabViewItemIndex == tabIndex)
            view.onClick = { [weak tabViewController] in
                tabViewController?.selectedTabViewItemIndex = tabIndex
            }

            item.view = view
            customTabItemViews[identity] = view
        }
    }

    @objc private func refreshTabSelectionState() {
        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }
        for (identity, view) in customTabItemViews {
            let matchingIndex = tabViewController.tabViewItems.firstIndex {
                ($0.identifier as? String) == identity
            }
            view.isSelected = (matchingIndex == tabViewController.selectedTabViewItemIndex)
        }
    }

    // MARK: Public

    // Action mapped to the + button in the PanelController. We should always open the General Pane when the + button is clicked.
    func openGeneralPane() {
        openPreferenceTab(at: 0)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens Settings to the Appearance tab. Used by AppDelegate to land
    /// the user back on the accent picker after a restart-to-apply-team
    /// relaunch.
    func openAppearancePane() {
        openPreferenceTab(at: 1)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openPreferenceTab(at index: Int) {
        guard let window = window else {
            return
        }

        if !window.isMainWindow || !window.isVisible {
            showWindow(nil)
        }

        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        tabViewController.selectedTabViewItemIndex = index
    }
}
