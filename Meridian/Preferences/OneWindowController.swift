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
        // AppKit re-paints toolbar tab text labels on its own schedule
        // (window key transitions, tab switches). Re-apply our tint on
        // those events so the team-coloured labels stay visible.
        if let win = window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reapplyToolbarTabTint),
                name: NSWindow.didBecomeKeyNotification,
                object: win
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reapplyToolbarTabTint),
                name: NSWindow.didUpdateNotification,
                object: win
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        setupWindow()
        setupToolbarImages()
        // Defer the label tint until after AppKit's first layout pass —
        // the toolbar's NSTextField subviews don't exist in the view
        // tree before that. The didBecomeKey notification handles
        // subsequent re-applications.
        DispatchQueue.main.async { [weak self] in
            self?.tintToolbarTabLabels()
        }
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
        let team = DataStore.shared().teamAccent.displayName
        Logger.production("[Accent] refreshToolbar fired: team=\(team)")
        setupToolbarImages()
        DispatchQueue.main.async { [weak self] in
            self?.tintToolbarTabLabels()
        }
    }

    @objc private func reapplyToolbarTabTint() {
        DispatchQueue.main.async { [weak self] in
            self?.tintToolbarTabLabels()
        }
    }

    /// Walks the window's NSThemeFrame view tree, finds NSTextFields whose
    /// stringValue matches one of our localised tab labels (Preferences,
    /// Appearance, About) and tints them with the active team accent.
    /// Necessary because tab-style NSTabViewController renders these
    /// labels through a private code path that ignores controlAccentColor.
    private func tintToolbarTabLabels() {
        guard let themeFrame = window?.contentView?.superview else { return }
        let teamColor = DataStore.shared().teamAccent.accentColor
        let labels: Set<String> = Set(Self.identifierToSymbol.keys.map {
            NSLocalizedString($0, comment: "")
        })
        Self.colorMatchingTextFields(in: themeFrame, labels: labels, color: teamColor)
    }

    private static func colorMatchingTextFields(in view: NSView, labels: Set<String>, color: NSColor) {
        if let field = view as? NSTextField, labels.contains(field.stringValue) {
            field.textColor = color
        }
        for sub in view.subviews {
            colorMatchingTextFields(in: sub, labels: labels, color: color)
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
