import Cocoa

// NSTextFieldCell renders its text top-anchored within any frame taller than
// the font's natural line height — this is documented behavior dating back to
// NeXTSTEP. With a 60pt-tall row and 30pt text, the result is text visibly
// pinned near the top of the cell.
//
// Override titleRect to compute a vertically-centered y position, and
// drawInterior to use it. select/edit overrides keep the field-editor
// rect aligned with the visible text when the cell goes into edit mode.
//
// Adapted from Daniel Jalkut, "What a Difference a Cell Makes":
// https://redsweater.com/blog/148/what-a-difference-a-cell-makes
class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private var isEditingOrSelecting = false

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleFrame = super.titleRect(forBounds: rect)
        let titleSize = attributedStringValue.size()
        titleFrame.origin.y = rect.origin.y + (rect.size.height - titleSize.height) / 2.0
        titleFrame.size.height = titleSize.height
        return titleFrame
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard !isEditingOrSelecting else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        attributedStringValue.draw(in: titleRect(forBounds: cellFrame))
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        isEditingOrSelecting = true
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
        isEditingOrSelecting = false
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        isEditingOrSelecting = true
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
        isEditingOrSelecting = false
    }
}
