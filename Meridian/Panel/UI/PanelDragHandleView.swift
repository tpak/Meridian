import Cocoa

/// A thin strip at the top of the floating panel that the user can grab to drag the window.
class PanelDragHandleView: NSView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds,
                                     options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate],
                                     owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw a row of subtle grip dots centred in the strip.
        NSColor.quaternaryLabelColor.setFill()
        let dotSize: CGFloat = 3
        let gap: CGFloat = 4
        let count = 5
        let totalW = CGFloat(count) * dotSize + CGFloat(count - 1) * gap
        var x = (bounds.width - totalW) / 2
        let y = (bounds.height - dotSize) / 2
        for _ in 0..<count {
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotSize, height: dotSize)).fill()
            x += dotSize + gap
        }
    }
}
