// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa

class AddTableViewCell: NSTableCellView {
    @IBOutlet var addTimezone: NSButton!

    override func awakeFromNib() {
        super.awakeFromNib()

        if let addCell = addTimezone.cell as? NSButtonCell {
            addCell.highlightsBy = .contentsCellMask
            addCell.showsStateBy = .pushInCellMask
        }

        addTimezone.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")

        addTimezone.setAccessibility("EmptyAddTimezone")
    }
}
