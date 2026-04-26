// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

class ModernSliderContainerView: NSView {
    private var trackingArea: NSTrackingArea?
    public var currentlyInFocus = false

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        currentlyInFocus = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        currentlyInFocus = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}

class ThinScroller: NSScroller {
    private var trackingArea: NSTrackingArea?

    override class func scrollerWidth(for _: NSControl.ControlSize, scrollerStyle _: NSScroller.Style) -> CGFloat {
        return 10
    }

    override func drawKnobSlot(in _: NSRect, highlight _: Bool) {
        // Leaving this empty to prevent background drawing
    }
}

class DraggableClipView: NSClipView {
    private var clickPoint: NSPoint!
    private var trackingArea: NSTrackingArea?

    // Called when the user lifts the mouse after dragging, so the controller can snap to the nearest item.
    var onDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        clickPoint = event.locationInWindow

        var gestureInProgress = true
        while gestureInProgress {
            let newEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .leftMouseDown])
            switch newEvent?.type {
            case .leftMouseDragged:
                guard let newPoint = newEvent?.locationInWindow else { break }
                let xDelta = clickPoint.x - newPoint.x
                let newOrigin = NSPoint(x: bounds.origin.x + xDelta, y: 0)
                let constrainedRect = constrainBoundsRect(NSRect(origin: newOrigin, size: bounds.size))
                scroll(to: constrainedRect.origin)
                superview?.reflectScrolledClipView(self)
                clickPoint = newPoint
            case .leftMouseDown:
                clickPoint = event.locationInWindow
            case .leftMouseUp:
                clickPoint = nil
                gestureInProgress = false
                onDragEnded?()
            default:
                Logger.debug("Default mouse event occurred for \(event.type)")
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}
