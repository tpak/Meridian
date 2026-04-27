import Cocoa

// NSButtonCell that vertically centers its checkbox glyph within the cell
// frame. The default NSButtonCell anchors the glyph to the top of the cell,
// which leaves it visibly misaligned in tall rows.
//
// Installed programmatically by PreferencesViewController.installCenteredFavouriteCheckbox.
class CenteredCheckboxCell: NSButtonCell {
    private func centeredFrame(in cellFrame: NSRect) -> NSRect {
        let natural = cellSize
        let height = min(cellFrame.height, natural.height)
        let yOffset = max(0, (cellFrame.height - height) / 2)
        return NSRect(
            x: cellFrame.origin.x,
            y: cellFrame.origin.y + yOffset,
            width: cellFrame.width,
            height: height
        )
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: centeredFrame(in: cellFrame), in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredFrame(in: cellFrame), in: controlView)
    }

    override func hitTest(for event: NSEvent, in cellFrame: NSRect, of controlView: NSView) -> NSCell.HitResult {
        return super.hitTest(for: event, in: centeredFrame(in: cellFrame), of: controlView)
    }
}
