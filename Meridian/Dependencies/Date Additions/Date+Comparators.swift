//
//  Date+Comparators.swift
//  DateToolsTests
//
//  Created by Matthew York on 8/26/16.
//  Copyright © 2016 Matthew York. All rights reserved.
//
//  TRIMMED (Meridian, issue #198): upstream DateTools shipped ~50 comparison helpers here —
//  chunkBetween, isEarlier/isLater, and the years/months/weeks/days/hours/minutes/seconds
//  Until/Ago/Earlier/Later families. Meridian called exactly one of them, so the rest are gone.
//  `chunkBetween` was also the last thing holding TimeChunk.swift alive.
//  Recover any of it from git history if a future caller needs it.
//

import Foundation

public extension Date {
    /**
     *  Returns an Int representing the amount of time in hours between the receiver and
     *  the provided date.
     *
     *  If the receiver is earlier than the provided date, the returned value will be negative.
     *
     *  - parameter date: The provided date for comparison
     *
     *  - returns: The hours between receiver and provided date
     */
    func hours(from date: Date) -> Int {
        // Upstream divided by Constants.SecondsInHour; that class existed only to be a bundle
        // anchor elsewhere, so the literal is inlined here rather than kept alive for one divisor.
        return Int(timeIntervalSince(date) / 3600)
    }

    /**
     *  Returns an Int representing the amount of time in days between the receiver and
     *  the provided date.
     *
     *  If the receiver is earlier than the provided date, the returned value will be negative.
     *
     *  - parameter date: The provided date for comparison
     *  - parameter calendar: The calendar to be used in the calculation
     *
     *  - returns: The days between receiver and provided date
     */
    func days(from date: Date, calendar: Calendar?) -> Int {
        var calendarCopy = calendar
        if calendar == nil {
            calendarCopy = Calendar.autoupdatingCurrent
        }

        let earliest = earlierDate(date)
        let latest = (earliest == self) ? date : self
        let multiplier = (earliest == self) ? -1 : 1
        let components = calendarCopy!.dateComponents([.day], from: earliest, to: latest)
        return multiplier * components.day!
    }
}
