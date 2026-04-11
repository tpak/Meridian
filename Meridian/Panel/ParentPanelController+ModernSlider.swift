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

            // Set the modern slider label!
            closestQuarterTimeRepresentation = timeScrollerViewModel.findClosestQuarterTimeApproximation()
            if let unwrappedClosetQuarterTime = closestQuarterTimeRepresentation {
                modernSliderLabel.stringValue = timezoneFormattedStringRepresentation(unwrappedClosetQuarterTime)
            }

            // Make sure modern slider is centered horizontally!
            let indexPaths: Set<IndexPath> = Set([IndexPath(item: modernSlider.numberOfItems(inSection: 0) / 2, section: 0)])
            modernSlider.scrollToItems(at: indexPaths, scrollPosition: .centeredHorizontally)
        }
    }

    @IBAction func goForward(_: NSButton) {
        navigateModernSliderToSpecificIndex(1)
    }

    @IBAction func goBackward(_: NSButton) {
        navigateModernSliderToSpecificIndex(-1)
    }

    private func animateResetButton(hidden: Bool) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: hidden ? CAMediaTimingFunctionName.easeOut : CAMediaTimingFunctionName.easeIn)
            resetModernSliderButton.animator().alphaValue = hidden ? 0.0 : 1.0
        }, completionHandler: { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.resetModernSliderButton.animator().isHidden = hidden
        })
    }

    private func setAccessoryButtons(hidden: Bool) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: hidden ? CAMediaTimingFunctionName.easeOut : CAMediaTimingFunctionName.easeIn)
            goForwardButton.animator().alphaValue = hidden ? 0.0 : 1.0
            goBackwardsButton.animator().alphaValue = hidden ? 0.0 : 1.0
        }, completionHandler: nil)
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

    private func navigateModernSliderToSpecificIndex(_ index: Int) {
        guard let contentView = modernSlider.superview as? NSClipView else {
            return
        }
        let changedOrigin = contentView.documentVisibleRect.origin
        let newPoint = NSPoint(x: changedOrigin.x + contentView.frame.width / 2, y: changedOrigin.y)
        if let indexPath = modernSlider.indexPathForItem(at: newPoint) {
            let previousIndexPath = IndexPath(item: indexPath.item + index, section: indexPath.section)
            modernSlider.scrollToItems(at: Set([previousIndexPath]), scrollPosition: .centeredHorizontally)
        }
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

    public func findClosestQuarterTimeApproximation() -> Date {
        return timeScrollerViewModel.findClosestQuarterTimeApproximation()
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

    private func timezoneFormattedStringRepresentation(_ date: Date) -> String {
        let dateFormatter = DateFormatterManager.dateFormatterWithFormat(with: .none,
                                                                         format: "MMM d HH:mm",
                                                                         timezoneIdentifier: TimeZone.current.identifier,
                                                                         locale: Locale.autoupdatingCurrent)
        return dateFormatter.string(from: date)
    }
}
