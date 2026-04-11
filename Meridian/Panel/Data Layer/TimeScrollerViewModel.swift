// Copyright © 2015 Abhishek Banthia

import Foundation

struct TimeScrollerViewModel {
    private let dataStore: DataStoring

    init(dataStore: DataStoring) {
        self.dataStore = dataStore
    }

    func totalSliderPoints() -> Int {
        let futureSliderDayPreference = dataStore.retrieve(key: UserDefaultKeys.futureSliderRange) as? NSNumber ?? 6
        let futureSliderDayRange = futureSliderDayPreference.intValue
        return (PanelConstants.modernSliderPointsInADay * futureSliderDayRange * 2) + 1
    }

    func calculateMinutesToAdd(for index: Int, baseDate: Date, now: Date = Date()) -> (Int, String) {
        let totalCount = totalSliderPoints()
        let centerPoint = Int(ceil(Double(totalCount / 2)))

        if index >= (centerPoint + 1) {
            let remainder = (index % (centerPoint + 1))
            let minuteOffset = remainder * PanelConstants.minutesPerSliderPoint
            let nextDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: baseDate)!
            let label = timezoneFormattedStringRepresentation(nextDate)
            return (nextDate.minutes(from: now) + 1, label)
        } else if index < centerPoint {
            let remainder = centerPoint - index + 1
            let minuteOffset = -1 * remainder * PanelConstants.minutesPerSliderPoint
            let previousDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: baseDate)!
            let label = timezoneFormattedStringRepresentation(previousDate)
            return (previousDate.minutes(from: now), label)
        } else {
            return (0, "Time Scroller")
        }
    }

    func findClosestQuarterTimeApproximation() -> Date {
        let defaultParameters = minuteFromCalendar()
        let hourQuarterDate = Calendar.current.nextDate(after: defaultParameters.0,
                                                        matching: DateComponents(minute: defaultParameters.1),
                                                        matchingPolicy: .strict,
                                                        repeatedTimePolicy: .first,
                                                        direction: .forward)!
        return hourQuarterDate
    }

    private func minuteFromCalendar() -> (Date, Int) {
        let currentDate = Date()
        var minute = Calendar.current.component(.minute, from: currentDate)
        if minute < 15 {
            minute = 15
        } else if minute < 30 {
            minute = 30
        } else if minute < 45 {
            minute = 45
        } else {
            minute = 0
        }

        return (currentDate, minute)
    }

    func timezoneFormattedStringRepresentation(_ date: Date) -> String {
        let dateFormatter = DateFormatterManager.dateFormatterWithFormat(with: .none,
                                                                         format: "MMM d HH:mm",
                                                                         timezoneIdentifier: TimeZone.current.identifier,
                                                                         locale: Locale.autoupdatingCurrent)
        return dateFormatter.string(from: date)
    }
}
