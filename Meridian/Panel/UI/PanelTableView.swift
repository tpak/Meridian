// Copyright © 2015 Abhishek Banthia

import Cocoa

protocol PanelTableViewDelegate: NSTableViewDelegate {
    func tableView(_ table: NSTableView, didHoverOver row: NSInteger)
}

class PanelTableView: NSTableView {
    weak var panelDelegate: PanelTableViewDelegate?
    private var trackingArea: NSTrackingArea?
    private(set) var hoverRow: Int = -1

    override func updateTrackingAreas() {
        if let tracker = trackingArea {
            removeTrackingArea(tracker)
        }

        createTrackingArea()

        super.updateTrackingAreas()
    }

    private func createTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .mouseEnteredAndExited,
            .activeAlways
        ]
        let clipRect = enclosingScrollView?.contentView.bounds ?? .zero

        trackingArea = NSTrackingArea(rect: clipRect,
                                      options: options,
                                      owner: self,
                                      userInfo: nil)

        if let tracker = trackingArea {
            addTrackingArea(tracker)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        let mousePointInWindow = event.locationInWindow
        let mousePoint = convert(mousePointInWindow, from: nil)
        var currentHoverRow = row(at: mousePoint)

        if currentHoverRow != hoverRow {
            // We've scrolled off the end of the table

            if currentHoverRow < 0 || currentHoverRow >= numberOfRows {
                currentHoverRow = -1
            }

            setHoverRow(currentHoverRow)
        }
    }

    private func setHoverRow(_ row: Int) {
        if row != hoverRow {
            hoverRow = row
            panelDelegate?.tableView(self, didHoverOver: hoverRow)
            // setNeedsDisplay is deprecated in 10.14
            needsDisplay = true
        }
    }

    override func reloadData() {
        super.reloadData()
        setHoverRow(-1)
        evaluateForHighlight()
    }

    private func evaluateForHighlight() {
        guard let mousePointInWindow = window?.mouseLocationOutsideOfEventStream else {
            return
        }

        let mousePoint = convert(mousePointInWindow, from: nil)
        evaluateForHighlight(at: mousePoint)
    }

    private func evaluateForHighlight(at point: NSPoint) {
        var hover = row(at: point)

        if hover != hoverRow {
            if hover < 0 || hover >= numberOfRows {
                hover = -1
            }
        }

        setHoverRow(hover)
    }

    override func mouseMoved(with event: NSEvent) {
        let mousePointInWindow = event.locationInWindow
        let mousePoint = convert(mousePointInWindow, from: nil)
        evaluateForHighlight(at: mousePoint)
    }
}
