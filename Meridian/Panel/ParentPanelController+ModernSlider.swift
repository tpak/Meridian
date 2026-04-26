// Copyright © 2015 Abhishek Banthia

import AppKit
import CoreLoggerKit
import Foundation

extension ParentPanelController: NSCollectionViewDataSource {
    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        return timeScrollerViewModel.totalSliderPoints()
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(withIdentifier: TimeMarkerViewItem.reuseIdentifier, for: indexPath) as? TimeMarkerViewItem else {
            return NSCollectionViewItem()
        }
        item.setup(with: indexPath.item)
        return item
    }
}

extension ParentPanelController {
    func setupModernSliderIfNeccessary() {
        if modernSlider != nil {
            modernSliderLabel.alignment = .center

            resetModernSliderButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset slider")

            if let scrollView = modernSlider.superview?.superview as? NSScrollView {
                scrollView.scrollerStyle = NSScroller.Style.overlay
            }

            for btn in [goBackwardsButton, goForwardButton] {
                btn?.imagePosition = .imageOnly
                btn?.isBordered = false
                btn?.bezelStyle = .recessed
            }
            goBackwardsButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Go backwards")
            goForwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Go forward")

            goForwardButton.isContinuous = true
            goBackwardsButton.isContinuous = true

            goBackwardsButton.toolTip = "Navigate 15 mins back"
            goForwardButton.toolTip = "Navigate 15 mins forward"

            modernSlider.wantsLayer = true // Required for animating reset to center
            modernSlider.enclosingScrollView?.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            modernSlider.enclosingScrollView?.backgroundColor = NSColor.clear
            modernSlider.setAccessibility("ModernSlider")
            modernSlider.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(collectionViewDidScroll(_:)),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: modernSlider.superview)

            // Wire up snap-to-grid after a drag gesture ends.
            if let clipView = modernSlider.superview as? DraggableClipView {
                clipView.onDragEnded = { [weak self] in
                    self?.snapSliderToCurrentItem()
                }
            }

            // Set the modern slider label!
            closestQuarterTimeRepresentation = timeScrollerViewModel.findClosestQuarterTimeApproximation()
            if let unwrappedClosetQuarterTime = closestQuarterTimeRepresentation {
                modernSliderLabel.stringValue = timeScrollerViewModel.timezoneFormattedStringRepresentation(unwrappedClosetQuarterTime)
            }

            // Make sure modern slider is centered horizontally and seed currentCenterIndexPath.
            let centerItem = modernSlider.numberOfItems(inSection: 0) / 2
            currentCenterIndexPath = centerItem
            let indexPaths: Set<IndexPath> = Set([IndexPath(item: centerItem, section: 0)])
            modernSlider.scrollToItems(at: indexPaths, scrollPosition: .centeredHorizontally)
        }
    }

    @IBAction func goForward(_: NSButton) {
        navigateModernSliderToSpecificIndex(1)
    }

    @IBAction func goBackward(_: NSButton) {
        navigateModernSliderToSpecificIndex(-1)
    }

    private func animateButton(_ button: NSButton, hidden: Bool) {
        if !hidden {
            button.alphaValue = 0
            button.isHidden = false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: hidden ? .easeOut : .easeIn)
            button.animator().alphaValue = hidden ? 0.0 : 1.0
        }, completionHandler: hidden ? { button.isHidden = true } : nil)
    }

    private func animateResetButton(hidden: Bool) {
        animateButton(resetModernSliderButton, hidden: hidden)
    }

    private func setAccessoryButtons(hidden: Bool) {
        animateButton(goForwardButton, hidden: hidden)
        animateButton(goBackwardsButton, hidden: hidden)
    }

    @IBAction func resetModernSlider(_: NSButton) {
        closestQuarterTimeRepresentation = timeScrollerViewModel.findClosestQuarterTimeApproximation()
        modernSliderLabel.stringValue = "Time Scroller"
        if modernSlider != nil {
            let indexPaths: Set<IndexPath> = Set([IndexPath(item: modernSlider.numberOfItems(inSection: 0) / 2, section: 0)])
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)
                modernSlider.animator().scrollToItems(at: indexPaths, scrollPosition: .centeredHorizontally)
            }, completionHandler: { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.animateResetButton(hidden: true)
                strongSelf.setAccessoryButtons(hidden: true)
            })
        }
    }

    private func snapSliderToCurrentItem() {
        guard currentCenterIndexPath >= 0 else { return }
        modernSlider.scrollToItems(at: [IndexPath(item: currentCenterIndexPath, section: 0)],
                                   scrollPosition: .centeredHorizontally)
    }

    private func navigateModernSliderToSpecificIndex(_ index: Int) {
        guard modernSlider != nil else { return }
        let total = modernSlider.numberOfItems(inSection: 0)
        let base = currentCenterIndexPath >= 0 ? currentCenterIndexPath : total / 2
        let target = max(0, min(base + index, total - 1))
        modernSlider.scrollToItems(at: [IndexPath(item: target, section: 0)],
                                   scrollPosition: .centeredHorizontally)
    }

    func jumpToSliderMinutes(_ minutes: Int) {
        guard modernSlider != nil else {
            setTimezoneDatasourceSlider(sliderValue: minutes)
            mainTableView.reloadData()
            return
        }
        let total = modernSlider.numberOfItems(inSection: 0)
        let center = total / 2
        let pointSize = PanelConstants.minutesPerSliderPoint
        // Round to nearest 15-min mark (slider's visual position only — collection
        // view items are discrete). Floor-divide would always pick the earlier
        // mark, so 7:32 would land at 7:30 even though 7:30 is further from the
        // user's intent than 7:30 → 7:32 → 7:45 (closer to 7:30 by 2 min).
        let itemsFromCenter = Int((Double(minutes) / Double(pointSize)).rounded())
        let target = max(0, min(center + itemsFromCenter, total - 1))
        currentCenterIndexPath = target
        // Update the slider's center label to reflect the snapped time.
        _ = setDefaultDateLabel(target)
        // BUT: drive every cell's displayed time from the EXACT minutes the user
        // typed, not the rounded slider position. Otherwise typing 7:32 would
        // show 7:30 in every row, which is the bug we're fixing.
        setTimezoneDatasourceSlider(sliderValue: minutes)
        mainTableView.reloadData()
        modernSlider.scrollToItems(at: [IndexPath(item: target, section: 0)], scrollPosition: .centeredHorizontally)
        setAccessoryButtons(hidden: minutes == 0)
        animateResetButton(hidden: minutes == 0)
    }

    @objc func collectionViewDidScroll(_ notification: NSNotification) {
        guard let contentView = notification.object as? NSClipView else {
            return
        }

        let changedOrigin = contentView.documentVisibleRect.origin
        let newPoint = NSPoint(x: changedOrigin.x + contentView.frame.width / 2, y: changedOrigin.y)
        let indexPath = modernSlider.indexPathForItem(at: newPoint)
        if let correctIndexPath = indexPath?.item, currentCenterIndexPath != correctIndexPath {
            setAccessoryButtons(hidden: false)
            currentCenterIndexPath = correctIndexPath
            let minutesToAdd = setDefaultDateLabel(correctIndexPath)
            setTimezoneDatasourceSlider(sliderValue: minutesToAdd)
            mainTableView.reloadData()
        }
    }

    public func setDefaultDateLabel(_ index: Int) -> Int {
        let baseDate = closestQuarterTimeRepresentation ?? Date()
        let result = timeScrollerViewModel.calculateMinutesToAdd(for: index, baseDate: baseDate)
        modernSliderLabel.stringValue = result.1
        if result.0 != 0 {
            if resetModernSliderButton.isHidden {
                animateResetButton(hidden: false)
            }
        } else {
            if !resetModernSliderButton.isHidden {
                animateResetButton(hidden: true)
            }
        }
        return result.0
    }

}
