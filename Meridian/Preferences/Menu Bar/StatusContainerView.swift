// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLoggerKit
import CoreModelKit

func compactWidth(for timezone: TimezoneData, with store: DataStore) -> Int {
    var totalWidth = MenubarLayoutConstants.baseWidth
    let timeFormat = timezone.timezoneFormat(store.timezoneFormat())

    if store.shouldShowDayInMenubar() {
        totalWidth += MenubarLayoutConstants.dayBuffer
    }

    if timeFormat == DateFormat.twelveHour
        || timeFormat == DateFormat.twelveHourWithSeconds
        || timeFormat == DateFormat.twelveHourWithZero
        || timeFormat == DateFormat.twelveHourWithSeconds {
        totalWidth += MenubarLayoutConstants.twelveHourBuffer
    } else if timeFormat == DateFormat.twentyFourHour
        || timeFormat == DateFormat.twentyFourHourWithSeconds {
        totalWidth += 0
    }

    if timezone.shouldShowSeconds(store.timezoneFormat()) {
        // Slight buffer needed when the Menubar supplementary text was Mon 9:27:58 AM
        totalWidth += MenubarLayoutConstants.secondsBuffer
    }

    if store.shouldShowDateInMenubar() {
        totalWidth += MenubarLayoutConstants.dateBuffer
    }

    return totalWidth
}

// Test with Sat 12:46 AM
let bufferWidth: CGFloat = 9.5

/// Height of the status-item content — always the live menu-bar thickness so the item fills the bar
/// exactly (measured: 22pt on this hardware). A taller item overflows the bar and shoves the
/// two-line stacked content down onto the bottom edge; matching the bar keeps both the single line
/// and the stacked pair vertically centred (#142 UAT).
var menubarItemHeight: CGFloat { NSStatusBar.system.thickness }

protocol StatusItemViewConforming {
    /// Mark that we need to refresh the text we're showing in the menubar
    func statusItemViewSetNeedsDisplay()

    /// Distinguish between different status items view through this identifier
    func statusItemViewIdentifier() -> String
}

/// Observe for User Default changes for timezones in App Delegate and reconstruct the Status View if neccesary
/// We'll inject the menubar timezones into Status Container View which'll pass it to StatusItemView
/// The benefit of doing so is reducing time-spent calculating menubar timezones and deserialization through `TimezoneData.customObject`
///  Also inject, `shouldDisplaySecondsInMenubar`
///

class StatusContainerView: NSView {
    private var previousX: Int = 0
    private let store: DataStore
    private var cachedBestWidth: [String: Int] = [:]
    private lazy var paragraphStyle: NSMutableParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        // Better readability for p,q,y,g in the status bar.
        let userPreferredLanguage = Locale.preferredLanguages.first ?? "en-US"
        let lineHeight = userPreferredLanguage.contains("en") ? LayoutConstants.englishMenubarLineHeightMultiple : 1
        paragraphStyle.lineHeightMultiple = CGFloat(lineHeight)
        return paragraphStyle
    }()

    override func awakeFromNib() {
        super.awakeFromNib()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    init(with timezones: [TimezoneData],
         store: DataStore,
         bufferContainerWidth: Int) {
        self.store = store

        let timeBasedAttributes = [
            NSAttributedString.Key.font: compactModeTimeFont,
            NSAttributedString.Key.backgroundColor: NSColor.clear,
            NSAttributedString.Key.paragraphStyle: defaultParagraphStyle
        ]

        func containerWidth(for timezones: [TimezoneData]) -> CGFloat {
            let compressedWidth = timezones.reduce(0.0) { result, timezoneObject -> CGFloat in
                let operationObject = TimezoneDataOperations(with: timezoneObject, store: store)
                if kMenubarV4SingleLine {
                    // Measure the actual single line ("● NAME TIME"); a generous width avoids
                    // truncating the measurement itself.
                    let lineSize = compactModeTimeFont.size(for: operationObject.compactMenuOneLine(),
                                                            width: 1000, attributes: timeBasedAttributes)
                    let dotPad: CGFloat = menubarColorDotsEnabled ? MenubarLayoutConstants.colorDotPadding : 0
                    return result + lineSize.width + dotPad + bufferWidth
                }
                let precalculatedWidth = Double(compactWidth(for: timezoneObject, with: store))
                let calculatedSubtitleSize = compactModeTimeFont.size(for: operationObject.compactMenuSubtitle(),
                                                                      width: precalculatedWidth,
                                                                      attributes: timeBasedAttributes)
                let calculatedTitleSize = compactModeTimeFont.size(for: operationObject.compactMenuTitle(),
                                                                   width: precalculatedWidth,
                                                                   attributes: timeBasedAttributes)
                let showSeconds = timezoneObject.shouldShowSeconds(store.timezoneFormat())
                let secondsBuffer: CGFloat = showSeconds ? MenubarLayoutConstants.measuredSecondsBuffer : 0
                return result + max(calculatedTitleSize.width, calculatedSubtitleSize.width) + bufferWidth + secondsBuffer
            }

            // The single-line width is measured directly, so don't clamp to the two-line cap.
            if kMenubarV4SingleLine { return compressedWidth }
            return min(compressedWidth, CGFloat(timezones.count * bufferContainerWidth))
        }

        let statusItemWidth = containerWidth(for: timezones)
        let frame = NSRect(x: 0, y: 0, width: statusItemWidth, height: menubarItemHeight)
        super.init(frame: frame)

        timezones.forEach { addTimezone($0) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addTimezone(_ timezone: TimezoneData) {
        let calculatedWidth = bestWidth(for: timezone)
        let frame = NSRect(x: previousX, y: 0, width: calculatedWidth, height: Int(menubarItemHeight))

        let statusItemView = StatusItemView(frame: frame)
        statusItemView.dataObject = timezone

        addSubview(statusItemView)

        previousX += calculatedWidth
    }

    private func bestWidth(for timezone: TimezoneData) -> Int {
        let cacheKey = timezone.timezone()
        if let cached = cachedBestWidth[cacheKey] {
            return cached
        }

        let textColor = NSColor.white

        let timeBasedAttributes = [
            NSAttributedString.Key.font: compactModeTimeFont,
            NSAttributedString.Key.foregroundColor: textColor,
            NSAttributedString.Key.backgroundColor: NSColor.clear,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]

        let operation = TimezoneDataOperations(with: timezone, store: store)
        let result: Int
        if kMenubarV4SingleLine {
            let lineSize = compactModeTimeFont.size(for: operation.compactMenuOneLine(),
                                                    width: 1000, attributes: timeBasedAttributes)
            let dotPad: CGFloat = menubarColorDotsEnabled ? MenubarLayoutConstants.colorDotPadding : 0
            result = Int(lineSize.width + dotPad + bufferWidth)
        } else {
            let bestSize = compactModeTimeFont.size(for: operation.compactMenuSubtitle(),
                                                    width: Double(compactWidth(for: timezone, with: store)),
                                                    attributes: timeBasedAttributes)
            let bestTitleSize = compactModeTimeFont.size(for: operation.compactMenuTitle(),
                                                         width: Double(compactWidth(for: timezone, with: store)),
                                                         attributes: timeBasedAttributes)
            result = Int(max(bestSize.width, bestTitleSize.width) + bufferWidth)
        }
        cachedBestWidth[cacheKey] = result
        return result
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        cachedBestWidth.removeAll()
        super.setNeedsDisplay(invalidRect)
    }

    func updateTime() {
        if subviews.isEmpty {
            Logger.debug("Subviews count should > 0")
        }

        for view in subviews {
            if let conformingView = view as? StatusItemViewConforming {
                conformingView.statusItemViewSetNeedsDisplay()
            }
        }

        // See if frame's width needs any adjustment
        adjustWidthIfNeccessary()
    }

    private func adjustWidthIfNeccessary() {
        var newWidth: CGFloat = 0

        subviews.forEach {
            if let statusItem = $0 as? StatusItemView, statusItem.isHidden == false {
                // Determine what's the best width required to display the current string.
                let newBestWidth = CGFloat(bestWidth(for: statusItem.dataObject))

                // Let's note if the current width is too small/correct
                newWidth += statusItem.frame.size.width != newBestWidth ? newBestWidth : statusItem.frame.size.width

                statusItem.frame = CGRect(x: statusItem.frame.origin.x,
                                          y: statusItem.frame.origin.y,
                                          width: newBestWidth,
                                          height: statusItem.frame.size.height)
            }
        }

        if newWidth != frame.size.width, newWidth > frame.size.width + 2.0 {
            Logger.debug("Correcting our width to \(newWidth) and the previous width was \(frame.size.width)")
            // NSView move animation
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)
                let newFrame = CGRect(x: frame.origin.x, y: frame.origin.y, width: newWidth, height: frame.size.height)
                self.animator().frame = newFrame
            }
        }
    }
}
