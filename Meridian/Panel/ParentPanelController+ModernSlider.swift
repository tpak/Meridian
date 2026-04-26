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

    private func setResetButtonHidden(_ hidden: Bool) {
        resetModernSliderButton.alphaValue = 1.0
        resetModernSliderButton.isHidden = hidden
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
                self?.setResetButtonHidden(true)
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
        let itemsFromCenter = minutes / PanelConstants.minutesPerSliderPoint
        let target = max(0, min(center + itemsFromCenter, total - 1))
        currentCenterIndexPath = target
        let minutesToAdd = setDefaultDateLabel(target)
        setTimezoneDatasourceSlider(sliderValue: minutesToAdd)
        mainTableView.reloadData()
        modernSlider.scrollToItems(at: [IndexPath(item: target, section: 0)], scrollPosition: .centeredHorizontally)
        setResetButtonHidden(minutesToAdd == 0)
    }

    @objc func collectionViewDidScroll(_ notification: NSNotification) {
        guard let contentView = notification.object as? NSClipView else {
            return
        }

        let changedOrigin = contentView.documentVisibleRect.origin
        let newPoint = NSPoint(x: changedOrigin.x + contentView.frame.width / 2, y: changedOrigin.y)
        let indexPath = modernSlider.indexPathForItem(at: newPoint)
        if let correctIndexPath = indexPath?.item, currentCenterIndexPath != correctIndexPath {
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
        setResetButtonHidden(result.0 == 0)
        return result.0
    }

}
