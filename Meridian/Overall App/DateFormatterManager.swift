// Copyright © 2015 Abhishek Banthia

import Cocoa

enum DateFormatterManager {
    private static var dateFormatter = DateFormatter()
    private static var calendarDateFormatter = DateFormatter()
    private static var simpleFormatter = DateFormatter()
    private static var specializedFormatter = DateFormatter()
    private static var localizedDateFormatter = DateFormatter()
    private static var localizedSimpleFormatter = DateFormatter()
    private static var gregorianCalendar = Calendar(identifier: Calendar.Identifier.gregorian)
    private static var USLocale = Locale(identifier: "en_US")

    static func dateFormatter(with style: DateFormatter.Style, for timezoneIdentifier: String) -> DateFormatter {
        dateFormatter.dateStyle = style
        dateFormatter.timeStyle = style
        dateFormatter.locale = USLocale
        dateFormatter.timeZone = TimeZone(identifier: timezoneIdentifier)
        return dateFormatter
    }

    static func dateFormatterWithFormat(with style: DateFormatter.Style,
                                        format: String,
                                        timezoneIdentifier: String,
                                        locale: Locale = Locale(identifier: "en_US")) -> DateFormatter {
        if specializedFormatter.dateStyle != style {
            specializedFormatter.dateStyle = style
        }

        if specializedFormatter.timeStyle != style {
            specializedFormatter.timeStyle = style
        }

        if specializedFormatter.dateFormat != format {
            specializedFormatter.dateFormat = format
        }

        if specializedFormatter.timeZone.identifier != timezoneIdentifier {
            specializedFormatter.timeZone = TimeZone(identifier: timezoneIdentifier)
        }

        if specializedFormatter.locale.identifier != locale.identifier {
            specializedFormatter.locale = locale
        }

        return specializedFormatter
    }

    static func localizedFormatter(with format: String, for timezoneIdentifier: String, locale _: Locale = Locale.autoupdatingCurrent) -> DateFormatter {
        if localizedDateFormatter.dateStyle != .none {
            localizedDateFormatter.dateStyle = .none
        }
        if localizedDateFormatter.timeStyle != .none {
            localizedDateFormatter.timeStyle = .none
        }
        if localizedDateFormatter.dateFormat != format {
            localizedDateFormatter.dateFormat = format
        }
        if localizedDateFormatter.locale != Locale.autoupdatingCurrent {
            localizedDateFormatter.locale = Locale.autoupdatingCurrent
        }
        if localizedDateFormatter.timeZone?.identifier != timezoneIdentifier {
            localizedDateFormatter.timeZone = TimeZone(identifier: timezoneIdentifier)
        }
        return localizedDateFormatter
    }

    static func localizedSimpleFormatter(_ format: String) -> DateFormatter {
        if localizedSimpleFormatter.dateStyle != .none {
            localizedSimpleFormatter.dateStyle = .none
        }
        if localizedSimpleFormatter.timeStyle != .none {
            localizedSimpleFormatter.timeStyle = .none
        }
        if localizedSimpleFormatter.dateFormat != format {
            localizedSimpleFormatter.dateFormat = format
        }
        if localizedSimpleFormatter.locale != Locale.autoupdatingCurrent {
            localizedSimpleFormatter.locale = Locale.autoupdatingCurrent
        }
        return localizedSimpleFormatter
    }
}
