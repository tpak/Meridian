// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreModelKit

// MARK: - Layout Constants

private enum PanelLayoutConstants {
    static let standardRowHeight: CGFloat = 68.0
    static let maximumRowHeight: CGFloat = 88.0
    static let sunriseHeightBuffer: CGFloat = 8.0
    static let emptyStateHeight: CGFloat = 100.0
    static let screenEdgeBuffer: CGFloat = 100
    static let sliderVisibleScreenBuffer: CGFloat = 200
    static let sliderHiddenScreenBuffer: CGFloat = 300
    static let noteHeightAdjustment: CGFloat = 20.0
}

// MARK: - Layout

extension ParentPanelController {
    func screenHeight() -> CGFloat {
        guard let main = NSScreen.main else { return 100 }

        let mouseLocation = NSEvent.mouseLocation

        var current = main.frame.height

        let activeScreens = NSScreen.screens.filter { current -> Bool in
            NSMouseInRect(mouseLocation, current.frame, false)
        }

        if let main = activeScreens.first {
            current = main.frame.height
        }

        return current
    }

    func getAdjustedRowHeight(for object: TimezoneData?, _ currentHeight: CGFloat, userFontSize: NSNumber? = nil) -> CGFloat {
        let fontSize: NSNumber = userFontSize ?? (dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber ?? 4)
        let shouldShowSunrise = dataStore.shouldDisplay(.sunrise)

        var newHeight = currentHeight

        if newHeight <= PanelLayoutConstants.standardRowHeight {
            newHeight = 60.0
        }

        if newHeight >= PanelLayoutConstants.standardRowHeight {
            newHeight = fontSize == 4 ? PanelLayoutConstants.standardRowHeight : PanelLayoutConstants.standardRowHeight
            if let obj = object,
               TimezoneDataOperations(with: obj, store: dataStore).nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) != nil {
                newHeight += PanelLayoutConstants.noteHeightAdjustment
            }
        }

        if newHeight >= PanelLayoutConstants.maximumRowHeight {
            // Set it to 88 explicitly in case the row height is calculated to be higher.
            newHeight = PanelLayoutConstants.maximumRowHeight

            let ops = object.flatMap { TimezoneDataOperations(with: $0, store: dataStore) }
            if ops?.nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) == nil {
                newHeight -= PanelLayoutConstants.noteHeightAdjustment
            }
        }

        if shouldShowSunrise, object?.selectionType == .city {
            newHeight += PanelLayoutConstants.sunriseHeightBuffer
        }

        if object?.isSystemTimezone == true {
            newHeight += 5
        }

        newHeight += mainTableView.intercellSpacing.height

        return newHeight
    }

    func setScrollViewConstraint() {
        var totalHeight: CGFloat = 0.0
        let timezones = dataStore.timezoneObjects()

        // Cache font size preference once rather than re-fetching per row
        let cachedFontSize = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber

        for cellIndex in 0 ..< timezones.count {
            let currentObject = timezones[cellIndex]
            let rowRect = mainTableView.rect(ofRow: cellIndex)
            totalHeight += getAdjustedRowHeight(for: currentObject, rowRect.size.height, userFontSize: cachedFontSize)
        }

        // This is for the Add Cell View case
        if timezones.isEmpty {
            scrollViewHeight.constant = PanelLayoutConstants.emptyStateHeight
            return
        }

        if let userFontSize = cachedFontSize {
            if userFontSize == 4 {
                scrollViewHeight.constant = totalHeight + CGFloat(userFontSize.intValue * 2)
            } else {
                scrollViewHeight.constant = totalHeight + CGFloat(userFontSize.intValue * 2) * 3.0
            }
        }

        if scrollViewHeight.constant > (screenHeight() - PanelLayoutConstants.screenEdgeBuffer) {
            scrollViewHeight.constant = (screenHeight() - PanelLayoutConstants.screenEdgeBuffer)
        }

        // Past this guard the slider is visible; the height adjustment below
        // shrinks the scroll view to make room for it.
        guard dataStore.shouldDisplay(.futureSlider) else { return }
        if scrollViewHeight.constant >= (screenHeight() - PanelLayoutConstants.sliderVisibleScreenBuffer) {
            scrollViewHeight.constant = (screenHeight() - PanelLayoutConstants.sliderHiddenScreenBuffer)
        }
    }
}
