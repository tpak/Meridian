// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

class TimezoneDataSource: NSObject {
    var timezones: [TimezoneData] = []
    var sliderValue: Int = 0
    var dataStore: DataStoring

    init(items: [TimezoneData], store: DataStoring) {
        sliderValue = 0
        timezones = Array(items)
        dataStore = store
        super.init()
    }
}

extension TimezoneDataSource {
    func setSlider(value: Int) {
        sliderValue = value
    }

    func setItems(items: [TimezoneData]) {
        timezones = items
    }
}

extension TimezoneDataSource: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        var totalTimezones = timezones.count

        // If totalTimezone is 0, then we can show an option to add timezones
        if totalTimezones == 0 {
            totalTimezones += 1
        }

        return totalTimezones
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard !timezones.isEmpty else {
            if let addCellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "addCell"), owner: self) as? AddTableViewCell {
                return addCellView
            }

            Logger.info("Unable to create AddTableViewCell")
            return nil
        }

        let cellID = NSUserInterfaceItemIdentifier(rawValue: "timeZoneCell")
        guard let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? TimezoneCellView else {
            Logger.info("Unable to create tableviewcell")
            return NSView()
        }

        let currentModel = timezones[row]
        let operation = TimezoneDataOperations(with: currentModel, store: dataStore)

        cellView.sunriseSetTime.stringValue = operation.formattedSunriseTime(with: sliderValue)
        cellView.sunriseImage.image = currentModel.isSunriseOrSunset
            ? NSImage(systemSymbolName: "sunrise.fill", accessibilityDescription: "Sunrise")
            : NSImage(systemSymbolName: "sunset.fill", accessibilityDescription: "Sunset")
        cellView.sunriseImage.contentTintColor = currentModel.isSunriseOrSunset ? NSColor.systemYellow : NSColor.systemOrange
        cellView.relativeDate.stringValue = operation.date(with: sliderValue, displayType: .panel)
        cellView.rowNumber = row
        cellView.customName.stringValue = currentModel.formattedTimezoneLabel()
        cellView.time.stringValue = operation.time(with: sliderValue)
        cellView.noteLabel.toolTip = currentModel.note ?? UserDefaultKeys.emptyString
        cellView.currentLocationIndicator.isHidden = !currentModel.isSystemTimezone
        cellView.time.setAccessibilityIdentifier("ActualTime")
        cellView.relativeDate.setAccessibilityIdentifier("RelativeDate")
        if let note = currentModel.note, !note.isEmpty {
            cellView.noteLabel.stringValue = note
            cellView.noteLabel.isHidden = false
        } else if let value = operation.nextDaylightSavingsTransitionIfAvailable(with: sliderValue) {
            cellView.noteLabel.stringValue = value
            cellView.noteLabel.isHidden = false
        } else {
            cellView.noteLabel.stringValue = UserDefaultKeys.emptyString
            cellView.noteLabel.isHidden = true
        }
        cellView.layout(with: currentModel)
        cellView.setAccessibilityIdentifier(currentModel.formattedTimezoneLabel())
        cellView.setAccessibilityLabel(currentModel.formattedTimezoneLabel())

        return cellView
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard !timezones.isEmpty else {
            return 100
        }

        if let userFontSize = dataStore.retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber,
           timezones.count > row,
           let relativeDisplay = dataStore.retrieve(key: UserDefaultKeys.relativeDateKey) as? NSNumber {
            let model = timezones[row]
            let shouldShowSunrise = dataStore.shouldDisplay(.sunrise)

            var rowHeight: Int = userFontSize == 4 ? 60 : 65

            if relativeDisplay.intValue == 3 {
                rowHeight -= 5
            }

            if shouldShowSunrise, model.selectionType == .city {
                rowHeight += 8
            }

            if let note = model.note, !note.isEmpty {
                rowHeight += userFontSize.intValue + 15
            } else if TimezoneDataOperations(with: model, store: dataStore).nextDaylightSavingsTransitionIfAvailable(with: sliderValue) != nil {
                rowHeight += userFontSize.intValue + 15
            }

            if model.isSystemTimezone {
                rowHeight += 2
            }

            rowHeight += (userFontSize.intValue * 2)
            return CGFloat(rowHeight)
        }

        return 1
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard !timezones.isEmpty else {
            return []
        }

        if edge == .trailing {
            let swipeToDelete = NSTableViewRowAction(style: .destructive,
                                                     title: "Delete",
                                                     handler: { _, row in

                if self.timezones[row].isSystemTimezone {
                    self.showAlertForDeletingAHomeRow(row, tableView)
                    return
                }

                let indexSet = IndexSet(integer: row)

                tableView.removeRows(at: indexSet, withAnimation: NSTableView.AnimationOptions())

                guard let panelController = PanelController.panel() else { return }
                panelController.deleteTimezone(at: row)
            })

            swipeToDelete.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Delete")

            return [swipeToDelete]
        }

        return []
    }

    private func showAlertForDeletingAHomeRow(_ row: Int, _ tableView: NSTableView) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Confirm deleting the home row?"
        alert.informativeText = "This row is automatically updated when Meridian detects a system timezone change. Are you sure you want to delete this?"
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        let response = alert.runModal()
        if response.rawValue == 1000 {
            OperationQueue.main.addOperation {
                let indexSet = IndexSet(integer: row)

                tableView.removeRows(at: indexSet, withAnimation: NSTableView.AnimationOptions.slideUp)

                guard let panelController = PanelController.panel() else { return }
                panelController.deleteTimezone(at: row)
            }
        }
    }
}

extension TimezoneDataSource: PanelTableViewDelegate {
    func tableView(_ table: NSTableView, didHoverOver row: NSInteger) {
        for rowIndex in 0 ..< table.numberOfRows {
            if let rowCellView = table.view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? TimezoneCellView {
                if row == -1 {
                    rowCellView.extraOptions.alphaValue = 0.5
                    continue
                }

                rowCellView.extraOptions.alphaValue = (rowIndex == row) ? 1 : 0.5
                if rowIndex == row, let hoverString = hoverStringForSelectedRow(row: row), sliderValue == 0 {
                    rowCellView.relativeDate.stringValue = hoverString
                }
            }
        }
    }

    private func hoverStringForSelectedRow(row: Int) -> String? {
        let currentModel = timezones[row]
        if let timezone = TimeZone(identifier: currentModel.timezone()) {
            let offSet = Double(timezone.secondsFromGMT()) / 3600
            let localizedName = timezone.localizedName(for: .shortDaylightSaving, locale: Locale.autoupdatingCurrent) ?? "Error"
            if offSet == 0.0 {
                return "\(localizedName)"
            } else {
                let offSetSign = offSet > 0 ? "+" : UserDefaultKeys.emptyString
                let offsetString = "UTC\(offSetSign)\(offSet)"
                return "\(localizedName) (\(offsetString))"
            }
        }
        return nil
    }
}

extension TimezoneCellView {
    func layout(with model: TimezoneData) {
        let shouldDisplay = DataStore.shared().shouldDisplay(.sunrise) && !sunriseSetTime.stringValue.isEmpty

        sunriseSetTime.isHidden = !shouldDisplay
        sunriseImage.isHidden = !shouldDisplay

        setupLayout()
    }
}
