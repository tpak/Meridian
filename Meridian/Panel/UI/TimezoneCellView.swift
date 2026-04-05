// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

class TimezoneCellView: NSTableCellView {
    @IBOutlet var customName: NSTextField!
    @IBOutlet var relativeDate: NSTextField!
    @IBOutlet var time: NSTextField!
    @IBOutlet var sunriseSetTime: NSTextField!
    @IBOutlet var noteLabel: NSTextField!
    @IBOutlet var extraOptions: NSButton!
    @IBOutlet var sunriseImage: NSImageView!
    @IBOutlet var currentLocationIndicator: NSImageView!

    private enum ConstraintID {
        static let width = "width"
        static let customNameTopSpace = "custom-name-top-space"
        static let timeTopSpace = "time-top-space"
        static let height = "height"
    }

    private static let minimumFontSizeForTime: Int = 10
    private static let minimumFontSizeForLabel: Int = 8

    private var lastRelativeDateValue: String?
    private var lastSunriseValue: String?

    var rowNumber: NSInteger = -1
    var isPopoverDisplayed: Bool = false

    override func awakeFromNib() {
        if ProcessInfo.processInfo.arguments.contains(UserDefaultKeys.testingLaunchArgument) {
            extraOptions.isHidden = false
            return
        }

        sunriseSetTime.alignment = .right

        canDrawSubviewsIntoLayer = true

        extraOptions.setAccessibility("extraOptionButton")
        customName.setAccessibility("CustomNameLabelForCell")
        noteLabel.setAccessibility("NoteLabel")
        currentLocationIndicator.toolTip = "This row will be updated automatically if Meridian detects a system-level timezone change!"
    }

    func setTextColor(color: NSColor) {
        [relativeDate, customName, time, sunriseSetTime].forEach { $0?.textColor = color }
        noteLabel.textColor = .gray
    }

    func setupLayout() {
        guard let relativeFont = relativeDate.font,
              let sunriseFont = sunriseSetTime.font
        else {
            Logger.debug("Unable to convert to NSString")
            return
        }

        let currentRelativeDate = relativeDate.stringValue
        let currentSunrise = sunriseSetTime.stringValue
        guard currentRelativeDate != lastRelativeDateValue || currentSunrise != lastSunriseValue else { return }
        lastRelativeDateValue = currentRelativeDate
        lastSunriseValue = currentSunrise

        let relativeDateString = currentRelativeDate as NSString
        let sunriseString = currentSunrise as NSString

        let relativeWidth = relativeDateString.size(withAttributes: [.font: relativeFont]).width
        let sunriseWidth = sunriseString.size(withAttributes: [.font: sunriseFont]).width

        let hasRelativeDate = relativeDateString.length > 0
        updateRelativeDateVisibility(hasContent: hasRelativeDate, width: relativeWidth)
        updateTimeTopSpace(hasRelativeDate: hasRelativeDate)

        for constraint in sunriseSetTime.constraints where constraint.identifier == ConstraintID.width {
            constraint.constant = sunriseWidth + 3
        }

        setupTheme()
    }

    private func updateRelativeDateVisibility(hasContent: Bool, width: CGFloat) {
        guard hasContent else {
            relativeDate.isHidden = true
            if let c = constraints.first(where: { $0.identifier == ConstraintID.customNameTopSpace }),
               c.constant == 12 {
                c.constant += 15
            }
            return
        }

        if relativeDate.isHidden {
            relativeDate.isHidden.toggle()
        }
        if let c = relativeDate.constraints.first(where: { $0.identifier == ConstraintID.width }) {
            c.constant = width + 8
        }
        if let c = constraints.first(where: { $0.identifier == ConstraintID.customNameTopSpace }),
           c.constant != 12 {
            c.constant = 12
        }
    }

    private func updateTimeTopSpace(hasRelativeDate: Bool) {
        let sunriseVisible = !sunriseSetTime.isHidden

        for constraint in constraints where constraint.identifier == ConstraintID.timeTopSpace {
            if hasRelativeDate, sunriseVisible, relativeDate.isHidden {
                if constraint.constant == -5.0 { constraint.constant -= 10.0 }
            } else if hasRelativeDate {
                if constraint.constant != -5.0 { constraint.constant = -3.0 }
            } else if sunriseVisible {
                if constraint.constant == -5.0 { constraint.constant -= 15.0 }
            } else {
                if constraint.constant != -5.0 { constraint.constant = -5.0 }
            }
        }
    }

    private func setupTheme() {
        setTextColor(color: NSColor.labelColor)

        extraOptions.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Options")
        extraOptions.alternateImage = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Options")

        currentLocationIndicator.image = NSImage(systemSymbolName: "location.fill", accessibilityDescription: "Current Location")

        setupTextSize()
    }

    private func setupTextSize() {
        // TimezoneCellView is instantiated by NSTableView from a XIB and does not participate in the
        // DataStoring dependency-injection chain, so we fall back to the DataStore singleton here.
        guard let userFontSize = DataStore.shared().retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber else {
            Logger.debug("User Font Size is in unexpected format")
            return
        }

        guard let customFont = customName.font,
              let timeFont = time.font
        else {
            Logger.debug("User Font Size is unexpectedly nil")
            return
        }

        // Multiplier 1: label font grows 1pt per font-size step (subtle scaling for the place name).
        // Multiplier 2: time font grows 2pt per step (more prominent scaling for the clock readout).
        let newFontSize = CGFloat(TimezoneCellView.minimumFontSizeForLabel + (userFontSize.intValue * 1))
        let newTimeFontSize = CGFloat(TimezoneCellView.minimumFontSizeForTime + (userFontSize.intValue * 2))

        let fontManager = NSFontManager.shared

        let customPlaceFont = fontManager.convert(customFont, toSize: newFontSize)
        let customTimeFont = fontManager.convert(timeFont, toSize: newTimeFontSize)

        customName.font = customPlaceFont
        time.font = customTimeFont

        let timeString = time.stringValue as NSString
        let timeSize = timeString.size(withAttributes: [NSAttributedString.Key.font: customTimeFont])

        for constraint in time.constraints {
            constraint.constant = constraint.identifier == ConstraintID.height ? timeSize.height : timeSize.width
        }
    }

    @IBAction func showExtraOptions(_ sender: NSButton) {
        var searchView = superview

        while searchView != nil, searchView is PanelTableView == false {
            searchView = searchView?.superview
        }

        guard searchView is PanelTableView else {
            // We might be coming from the preview tableview!
            return
        }

        guard let panel = PanelController.panel() else { return }
        isPopoverDisplayed = panel.showNotesPopover(forRow: rowNumber,
                                                    relativeTo: bounds,
                                                    andButton: sender)

        Logger.debug("Open Extra Options")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            // Text is copied in the following format: Chicago - 1625185925
            let clipboardCopy = "\(customName.stringValue) - \(time.stringValue)"
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(clipboardCopy, forType: .string)

            window?.contentView?.makeToast("Copied to Clipboard".localized())

            window?.endEditing(for: nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Pass right-clicks up the responder chain (e.g. to PanelController for Pin to Desktop).
        // The old notes popover was removed in the strip commit; showExtraOptions would crash.
        super.rightMouseDown(with: event)
    }
}
