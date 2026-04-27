// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

class TimezoneCellView: NSTableCellView {
    @IBOutlet var customName: NSTextField!
    @IBOutlet var relativeDate: NSTextField!
    @IBOutlet var time: NSTextField!
    @IBOutlet var sunriseSetTime: NSTextField!
    @IBOutlet var dstLabel: NSTextField!
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
    var timezoneIdentifier: String = ""
    private(set) var isEditingTime: Bool = false

    // Local key event monitor active only while editing the time field.
    // Catches arrow keys at the application level so they reach the field
    // editor's caret motion instead of being consumed by NSTableView /
    // NSCollectionView further up the responder chain.
    private var arrowKeyMonitor: Any?

    override func awakeFromNib() {
        if ProcessInfo.processInfo.arguments.contains(UserDefaultKeys.testingLaunchArgument) {
            return
        }

        sunriseSetTime.alignment = .right

        canDrawSubviewsIntoLayer = true

        customName.setAccessibility("CustomNameLabelForCell")
        dstLabel.setAccessibility("DSTLabel")
        currentLocationIndicator.toolTip = "This row will be updated automatically if Meridian detects a system-level timezone change!"
    }

    func setTextColor(color: NSColor) {
        [relativeDate, customName, time, sunriseSetTime].forEach { $0?.textColor = color }
        dstLabel.textColor = .gray
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

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            beginTimeEntry()
            return
        }
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

    private func beginTimeEntry() {
        guard !timezoneIdentifier.isEmpty else { return }
        isEditingTime = true
        time.isEditable = true
        time.isBezeled = true
        time.bezelStyle = .roundedBezel
        time.delegate = self
        time.selectText(nil)
        installArrowKeyMonitor()
        Logger.production("Time edit begin for \(timezoneIdentifier)")
    }

    private func installArrowKeyMonitor() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isEditingTime else { return event }
            let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]  // left, right, down, up
            guard arrowKeyCodes.contains(event.keyCode) else { return event }
            // Route the arrow event explicitly to the field editor so the caret moves
            // and we don't lose focus to NSTableView's row-navigation handler.
            if let editor = self.time.currentEditor() {
                editor.keyDown(with: event)
            }
            return nil  // consume — don't let it propagate to other responders
        }
    }

    private func removeArrowKeyMonitor() {
        if let monitor = arrowKeyMonitor {
            NSEvent.removeMonitor(monitor)
            arrowKeyMonitor = nil
        }
    }

    private func restoreTimeField() {
        isEditingTime = false
        time.delegate = nil
        time.isEditable = false
        time.isBezeled = false
        removeArrowKeyMonitor()
    }

    private func commitTimeEntry() {
        let inputText = time.stringValue
        restoreTimeField()
        guard let panelController = PanelController.panel() else { return }
        let currentOffset = panelController.futureSliderValue
        let now = Date()
        let currentSliderDate = Calendar.current.date(byAdding: .minute, value: currentOffset, to: now) ?? now
        guard let tz = TimeZone(identifier: timezoneIdentifier),
              let targetDate = parseEnteredTime(inputText, in: tz, relativeTo: currentSliderDate) else {
            panelController.mainTableView.reloadData()
            return
        }
        let minutesOffset = Int(targetDate.timeIntervalSince(now) / 60.0)
        panelController.jumpToSliderMinutes(minutesOffset)
    }

    private func cancelTimeEntry() {
        restoreTimeField()
        PanelController.panel()?.mainTableView.reloadData()
    }

    private func parseEnteredTime(_ input: String, in timezone: TimeZone, relativeTo baseDate: Date) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let baseComponents = cal.dateComponents([.year, .month, .day], from: baseDate)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone

        for format in ["h:mm a", "h:mma", "H:mm", "h:mm", "ha", "h a", "H"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: trimmed) else { continue }
            var comps = baseComponents
            let timeComps = cal.dateComponents([.hour, .minute], from: parsed)
            comps.hour = timeComps.hour
            comps.minute = timeComps.minute
            comps.second = 0
            return cal.date(from: comps)
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        // Pass right-clicks up the responder chain (e.g. to PanelController for Pin to Desktop).
        super.rightMouseDown(with: event)
    }
}

extension TimezoneCellView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTimeEntry()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTimeEntry()
            return true
        }
        // Swallow arrow keys at the doCommandBy layer so NSText doesn't propagate
        // them up to NSTableView (which would change the selected row, ending the
        // edit session). Manually translate them into in-field caret motion.
        switch commandSelector {
        case #selector(NSResponder.moveLeft(_:)):
            textView.moveLeft(nil)
            return true
        case #selector(NSResponder.moveRight(_:)):
            textView.moveRight(nil)
            return true
        case #selector(NSResponder.moveUp(_:)),
             #selector(NSResponder.moveDown(_:)):
            // Single-line field — up/down are no-ops, but we still consume them
            // so the table view doesn't change selection out from under us.
            return true
        default:
            return false
        }
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        // If the user is just navigating with arrow keys, refuse to end editing.
        // controlTextDidEndEditing wouldn't fire if we return false here.
        if let event = NSApp.currentEvent, event.type == .keyDown {
            let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]  // left, right, down, up
            if arrowKeyCodes.contains(event.keyCode) {
                return false
            }
        }
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditingTime else { return }
        cancelTimeEntry()
    }
}
