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
    }

    private func setup() {
        setupWindow()
        setupToolbarImages()
    }

    private func setupWindow() {
        window?.titlebarAppearsTransparent = true
        window?.backgroundColor = NSColor.windowBackgroundColor
        window?.identifier = NSUserInterfaceItemIdentifier("Preferences")
    }

    private func setupToolbarImages() {
        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        let identifierToImageMapping: [String: NSImage] = [
            "Preferences Tab": NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage(),
            "Appearance Tab": NSImage(systemSymbolName: "paintbrush", accessibilityDescription: nil) ?? NSImage(),
            "About Tab": NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) ?? NSImage()
        ]

        tabViewController.tabViewItems.forEach { tabViewItem in
            let identity = (tabViewItem.identifier as? String) ?? ""
            if let image = identifierToImageMapping[identity] {
                tabViewItem.image = image
            }
        }
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
