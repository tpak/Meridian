import Cocoa

// NSButtonCell with type=check, bezelStyle=regularSquare, imagePosition=only
// renders its glyph via drawImage(_:withFrame:in:) — NOT via draw, drawInterior,
// imageRect, or drawingRect. The bezel is independently positioned at the top
// of the frame, so overriding the outer-draw methods does nothing visible.
// The fix is to recompute a vertically-centered sub-frame and forward to
// super.drawImage with it.
class CenteredCheckboxCell: NSButtonCell {
    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        let glyphSize = image.size
        let centered = NSRect(
            x: frame.origin.x + (frame.size.width - glyphSize.width) / 2.0,
            y: frame.origin.y + (frame.size.height - glyphSize.height) / 2.0,
            width: glyphSize.width,
            height: glyphSize.height
        )
        super.drawImage(image, withFrame: centered, in: controlView)
    }
}
