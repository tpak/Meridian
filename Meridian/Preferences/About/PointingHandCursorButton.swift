// Copyright © 2015 Abhishek Banthia

import Cocoa

class PointingHandCursorButton: NSButton {
    let pointingHandCursor: NSCursor = .pointingHand

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: pointingHandCursor)
    }
}
