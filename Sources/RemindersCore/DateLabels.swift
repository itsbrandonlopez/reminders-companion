import Foundation

/// Every user-facing date and time string in the app.
///
/// Two problems this exists to fix, both spread across ten separate `DateFormatter()`
/// constructions in five files.
///
/// **A fixed pattern is not localisation.** `dateFormat = "h:mm a"` renders 13:30 as
/// "1:30 PM" for a reader whose region uses a 24-hour clock, and did so everywhere a
/// deadline time appeared. `setLocalizedDateFormatFromTemplate` asks for the same *fields*
/// and lets the locale arrange them, which is what these strings actually want.
///
/// **Constructing a `DateFormatter` is expensive**, and every one of these sat in a computed
/// property called from a SwiftUI body — `TaskItem.dueTimeLabel` built one per visible row
/// per render. Built once here instead.
public enum DateLabels {

    // Shared globals, deliberately. `DateFormatter` carries a `Sendable` conformance and
    // is safe to *use* concurrently — what is unsafe is mutating one after the fact, which
    // nothing here does: each is configured on creation and only ever asked to format. Any
    // caller needing a different timezone builds its own rather than reaching in and
    // setting one (see `CalendarEvent.timeLabel`).
    //
    // Locale is captured once, so changing region mid-session needs an app restart to take
    // effect. That is the same tradeoff the hardcoded patterns made, only now in the
    // direction of being right for most readers rather than none.

    /// Time of day — "9:30 AM" or "09:30", by locale.
    public static let time = template("jmm")
    /// Day and month, no year — "20 Aug" or "Aug 20".
    public static let monthDay = template("dMMM")
    /// Day, month and year — for a repeat's end date, where the year carries meaning.
    public static let monthDayYear = template("dMMMyyyy")
    /// Abbreviated weekday — "Mon".
    public static let shortWeekday = template("EEE")
    /// Full weekday — "Monday".
    public static let fullWeekday = template("EEEE")
    /// Day, month and time, for an alarm — "20 Aug, 9:30 AM".
    public static let monthDayTime = template("dMMMjmm")

    private static func template(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(pattern)
        return formatter
    }
}

extension Day {
    /// "20 Aug".
    public var monthDayLabel: String { DateLabels.monthDay.string(from: startOfDay()) }
    /// "20 Aug 2026".
    public var monthDayYear: String { DateLabels.monthDayYear.string(from: startOfDay()) }
    /// "Mon".
    public var shortWeekday: String { DateLabels.shortWeekday.string(from: startOfDay()) }
    /// "Monday".
    public var fullWeekday: String { DateLabels.fullWeekday.string(from: startOfDay()) }

    public var isToday: Bool { self == Day.today() }
    public var isPast: Bool { self < Day.today() }

    /// The day number alone, for a calendar-style header.
    public var dayNumber: String { String(day) }

    /// "Today", "Tomorrow", "Yesterday", else the full weekday. What the phone's day
    /// headers show, where there is room for the long form.
    public var relativeName: String {
        if isToday { return "Today" }
        if self == Day.today().adding(days: 1) { return "Tomorrow" }
        if self == Day.today().adding(days: -1) { return "Yesterday" }
        return fullWeekday
    }

    /// "Today", "Tomorrow", else the abbreviated weekday.
    ///
    /// Kept distinct from `relativeName` rather than merged with it: a Lock Screen widget
    /// has room for "Mon" and not for "Monday", and it deliberately does not name yesterday
    /// — an overdue item there is already coloured as overdue.
    public var relativeShortLabel: String {
        if isToday { return "Today" }
        if self == Day.today().adding(days: 1) { return "Tomorrow" }
        return shortWeekday
    }
}
