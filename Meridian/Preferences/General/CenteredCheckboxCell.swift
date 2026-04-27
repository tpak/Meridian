import Cocoa

// NSButtonCell with type=check rendered inside a tall NSTableView cell
// draws the checkbox glyph at the top of the cell frame. Pass a vertically
// centered sub-frame to super's draw so the checkbox aligns with the city
// and label text in the adjacent columns. Hit-test rect is also centered
// so clicking the visible checkbox actually toggles state.
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
