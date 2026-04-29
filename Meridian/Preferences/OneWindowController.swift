// Copyright © 2015 Abhishek Banthia

import Cocoa

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

    /// Sets each NSTabViewItem's image to a freshly-allocated NSImage.
    /// Called at windowDidLoad and again from `refreshToolbarForAccentChange`
    /// when the user picks a new team accent — re-using the same NSImage
    /// instance is not enough to invalidate AppKit's tinted-bitmap cache
    /// for the toolbar tabs.
    private func setupToolbarImages() {
        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        let identifierToSymbol: [String: String] = [
            "Preferences Tab": "gearshape",
            "Appearance Tab": "paintbrush",
            "About Tab": "info.circle"
        ]

        tabViewController.tabViewItems.forEach { tabViewItem in
            let identity = (tabViewItem.identifier as? String) ?? ""
            if let symbol = identifierToSymbol[identity] {
                // Always create a NEW NSImage. AppKit's NSToolbarItem caches
                // the tinted bitmap of `tabViewItem.image` and the
                // identity-comparison check skips re-rendering when the same
                // NSImage instance is assigned, so swapping in a fresh
                // instance is what forces the re-tint.
                tabViewItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
        }
    }

    @objc private func refreshToolbarForAccentChange() {
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
