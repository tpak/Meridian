import Cocoa

// NSButtonCell with type=check rendered inside a tall NSTableView cell
// draws the checkbox glyph at the top of the cell frame. Override the
// drawing rect to vertically center it within the row so the favourite
// column reads aligned with the city/label text in adjacent columns.
class CenteredCheckboxCell: NSButtonCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let naturalSize = cellSize
        let yOffset = max(0, (rect.height - naturalSize.height) / 2)
        return NSRect(
            x: rect.origin.x,
            y: rect.origin.y + yOffset,
            width: rect.width,
            height: min(rect.height, naturalSize.height)
        )
    }
}
