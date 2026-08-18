import Foundation

/// Every conversion between a `Day` and the `DateComponents` EventKit wants.
///
/// This type exists because of one non-obvious Reminders behaviour the Phase 0 spike
/// uncovered: `allDay` is a property of the *reminder*, not of each date on it. Writing
/// an all-day start date therefore flips the whole item to all-day and silently strips
/// the time off a timed due date — turning "pay the mortgage, Friday 9:00 AM" into a
/// bare all-day item. See spike/FINDINGS.md for the captured before/after.
///
/// The rule that avoids it: a planned day must mirror the timed-ness of the due date it
/// sits alongside.
public enum Scheduling {

    /// Whether a set of date components carries a wall-clock time.
    public static func isTimed(_ components: DateComponents?) -> Bool {
        guard let c = components else { return false }
        return c.hour != nil || c.minute != nil || c.second != nil
    }

    /// Builds the `startDateComponents` to write when the user drops a task on `day`.
    ///
    /// - Parameter due: the reminder's existing due components, which decide the shape.
    ///   Timed due date → timed start at midnight in the due date's own timezone, keeping
    ///   the item non-all-day. All-day or absent due date → all-day floating start,
    ///   matching how Reminders itself writes undated-time items.
    public static func plannedComponents(for day: Day, alongside due: DateComponents?) -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.year = day.year
        c.month = day.month
        c.day = day.day

        if isTimed(due) {
            c.timeZone = due?.timeZone ?? .current
            c.hour = 0
            c.minute = 0
            c.second = 0
        }
        // Otherwise leave time and timezone nil: an all-day, floating date that cannot
        // drift when the machine changes timezone.
        return c
    }

    /// Builds the `dueDateComponents` to write when the user drags a task's span end.
    ///
    /// This is the **only** path in the app that writes a due date, and it exists because
    /// the far end of a multi-day span *is* the deadline. Any existing time of day is
    /// preserved — dragging the span of a bill due Friday 9:00 AM must not turn it into a
    /// bare all-day item. Alarms hold absolute dates and are never touched, so a reminder
    /// still notifies exactly when it did before.
    public static func deadlineComponents(
        for day: Day, preserving existing: DateComponents?
    ) -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.year = day.year
        c.month = day.month
        c.day = day.day

        if isTimed(existing) {
            c.timeZone = existing?.timeZone ?? .current
            c.hour = existing?.hour ?? 0
            c.minute = existing?.minute ?? 0
            c.second = existing?.second ?? 0
        }
        return c
    }

    /// The day a task should appear under on the week board.
    ///
    /// Planned day wins when present — that is the whole point of the start/due split.
    /// A task with only a deadline still needs to show up somewhere, so it falls back to
    /// its due day until it is explicitly planned.
    public static func boardDay(start: DateComponents?, due: DateComponents?) -> Day? {
        Day(start) ?? Day(due)
    }

    /// The inclusive span a task occupies, for rendering multi-day bars.
    /// Returns nil for tasks with no dates at all — those live in the backlog.
    public static func span(start: DateComponents?, due: DateComponents?) -> ClosedRange<Day>? {
        let s = Day(start)
        let d = Day(due)
        switch (s, d) {
        case let (.some(s), .some(d)): return s <= d ? s...d : d...s
        case let (.some(s), .none): return s...s
        case let (.none, .some(d)): return d...d
        case (.none, .none): return nil
        }
    }

    /// The seven days of the week containing `day`, starting on `firstWeekday`
    /// (1 = Sunday, 2 = Monday, matching `Calendar.firstWeekday`).
    public static func week(containing day: Day, firstWeekday: Int = 2) -> [Day] {
        var cal = Day.gregorian
        cal.timeZone = .current
        cal.firstWeekday = firstWeekday
        let date = day.startOfDay()
        let weekday = cal.component(.weekday, from: date)
        let offset = -((weekday - firstWeekday + 7) % 7)
        let start = Day(cal.date(byAdding: .day, value: offset, to: date) ?? date)
        return (0..<7).map { start.adding(days: $0) }
    }
}

/// Which column a task belongs in.
public enum Bucket: Equatable, Sendable {
    /// No date at all — the pool you plan a week from.
    case unscheduled
    /// Sits on a specific day, whether planned or merely due then.
    case day(Day)
    /// Dated, but the whole week it belonged to has already gone by.
    case backlog
}

extension Scheduling {
    /// Sorts a task into a board column.
    ///
    /// The backlog is not simply "overdue". Something due Monday when today is Tuesday
    /// stays on Monday, where the week in progress can still absorb it; only work that
    /// slipped past the *entire* current week falls out into the backlog. `currentWeekStart`
    /// is anchored to today rather than to the week being viewed, so paging forward to
    /// plan next week never sweeps this week's work into the backlog.
    public static func bucket(
        plannedDay: Day?,
        dueDay: Day?,
        currentWeekStart: Day
    ) -> Bucket {
        guard let day = plannedDay ?? dueDay else { return .unscheduled }
        return day < currentWeekStart ? .backlog : .day(day)
    }
}
