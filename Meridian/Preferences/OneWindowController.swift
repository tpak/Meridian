// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

class CenteredTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup localized tab labels
        tabViewItems.forEach { item in
            if let identifier = item.identifier as? String {
                item.label = NSLocalizedString(identifier, comment: "Tab View Item Label for \(identifier)")
            }
        }
    }
}

class OneWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
        setup()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshToolbarForAccentChange),
            name: .accentColorDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        setupWindow()
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
    }

    @objc private func refreshToolbarForAccentChange() {
        let count = window?.toolbar?.items.count ?? 0
        Logger.production("OneWindowController: refreshToolbarForAccentChange firing, toolbar.items.count=\(count)")
        setupToolbarImages()
    }

    // MARK: Public

    // Action mapped to the + button in the PanelController. We should always open the General Pane when the + button is clicked.
    func openGeneralPane() {
        openPreferenceTab(at: 0)
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
