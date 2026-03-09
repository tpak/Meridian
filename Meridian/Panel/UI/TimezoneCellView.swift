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

    private static let minimumFontSizeForTime: Int = 10
    private static let minimumFontSizeForLabel: Int = 8

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
            Logger.info("Unable to convert to NSString")
            return
        }

        let relativeDateString = relativeDate.stringValue as NSString
        let sunriseString = sunriseSetTime.stringValue as NSString

        let relativeWidth = relativeDateString.size(withAttributes: [.font: relativeFont]).width
        let sunriseWidth = sunriseString.size(withAttributes: [.font: sunriseFont]).width

        let hasRelativeDate = relativeDateString.length > 0
        updateRelativeDateVisibility(hasContent: hasRelativeDate, width: relativeWidth)
        updateTimeTopSpace(hasRelativeDate: hasRelativeDate)

        for constraint in sunriseSetTime.constraints where constraint.identifier == "width" {
            constraint.constant = sunriseWidth + 3
        }

        setupTheme()
    }

    private func updateRelativeDateVisibility(hasContent: Bool, width: CGFloat) {
        if hasContent {
            if relativeDate.isHidden {
                relativeDate.isHidden.toggle()
            }
            for constraint in relativeDate.constraints where constraint.identifier == "width" {
                constraint.constant = width + 8
            }
            for constraint in constraints where constraint.identifier == "custom-name-top-space" {
                if constraint.constant != 12 {
                    constraint.constant = 12
                }
            }
        } else {
            relativeDate.isHidden = true
            for constraint in constraints where constraint.identifier == "custom-name-top-space" {
                if constraint.constant == 12 {
                    constraint.constant += 15
                }
            }
        }
    }

    private func updateTimeTopSpace(hasRelativeDate: Bool) {
        let sunriseVisible = !sunriseSetTime.isHidden

        for constraint in constraints where constraint.identifier == "time-top-space" {
            if hasRelativeDate {
                if sunriseVisible, relativeDate.isHidden {
                    if constraint.constant == -5.0 { constraint.constant -= 10.0 }
                } else if constraint.constant != -5.0 {
                    constraint.constant = -3.0
                }
            } else {
                if sunriseVisible {
                    if constraint.constant == -5.0 { constraint.constant -= 15.0 }
                } else if constraint.constant != -5.0 {
                    constraint.constant = -5.0
                }
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
        guard let userFontSize = DataStore.shared().retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber else {
            Logger.info("User Font Size is in unexpected format")
            return
        }

        guard let customFont = customName.font,
              let timeFont = time.font
        else {
            Logger.info("User Font Size is unexpectedly nil")
            return
        }

        let newFontSize = CGFloat(TimezoneCellView.minimumFontSizeForLabel + (userFontSize.intValue * 1))
        let newTimeFontSize = CGFloat(TimezoneCellView.minimumFontSizeForTime + (userFontSize.intValue * 2))

        let fontManager = NSFontManager.shared

        let customPlaceFont = fontManager.convert(customFont, toSize: newFontSize)
        let customTimeFont = fontManager.convert(timeFont, toSize: newTimeFontSize)

        customName.font = customPlaceFont
        time.font = customTimeFont

        let timeString = time.stringValue as NSString

        let timeHeight = timeString.size(withAttributes: [NSAttributedString.Key.font: customTimeFont]).height
        let timeWidth = timeString.size(withAttributes: [NSAttributedString.Key.font: customTimeFont]).width

        for constraint in time.constraints {
            constraint.constant = constraint.identifier == "height" ? timeHeight : timeWidth
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

        Logger.log(object: nil, for: "Open Extra Options")
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
        super.rightMouseDown(with: event)
        showExtraOptions(extraOptions)
        Logger.log(object: nil, for: "Right Click Open Options")
    }
}
