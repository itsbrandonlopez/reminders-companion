import Foundation

/// A calendar the overlay can draw from. Distinct from `TaskList` because none of the
/// reminder-list concepts (editable, Siri default) mean anything here — the overlay is
/// strictly read-only.
public struct EventCalendar: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let color: RGBA

    public init(id: String, title: String, color: RGBA) {
        self.id = id; self.title = title; self.color = color
    }
}

/// One occurrence of a calendar event, flattened for display.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// `eventIdentifier` is shared by every occurrence of a recurring event, so the
    /// occurrence's start date is folded in to keep ids unique within a week.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarID: String
    public let calendarName: String
    public let color: RGBA
    public let location: String?

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool,
        calendarID: String, calendarName: String, color: RGBA, location: String? = nil
    ) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.calendarID = calendarID
        self.calendarName = calendarName; self.color = color; self.location = location
    }

    /// The days this occurrence covers.
    ///
    /// End dates are treated as exclusive at the boundary: an all-day event ends at
    /// midnight on the following day, and a gig running until midnight should not paint
    /// the next morning. Both cases are handled by pulling the end back one second
    /// before bucketing.
    public func days(in timeZone: TimeZone = .current) -> ClosedRange<Day> {
        var calendar = Day.gregorian
        calendar.timeZone = timeZone
        let first = Day(start, in: calendar)
        let adjustedEnd = end > start ? end.addingTimeInterval(-1) : start
        let last = Day(adjustedEnd, in: calendar)
        return first <= last ? first...last : first...first
    }

    public func occupies(_ day: Day, in timeZone: TimeZone = .current) -> Bool {
        days(in: timeZone).contains(day)
    }

    public var durationMinutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    /// How this event reads in a day column. All-day events say so; a timed event shows
    /// its window; one that runs past midnight shows only where it starts, since the
    /// end belongs to a different column.
    public func timeLabel(on day: Day, in timeZone: TimeZone = .current) -> String {
        if isAllDay { return "All day" }

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"

        let span = days(in: timeZone)
        let startsHere = span.lowerBound == day
        let endsHere = span.upperBound == day

        switch (startsHere, endsHere) {
        case (true, true): return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        case (true, false): return "from \(formatter.string(from: start))"
        case (false, true): return "until \(formatter.string(from: end))"
        case (false, false): return "All day"
        }
    }
}
