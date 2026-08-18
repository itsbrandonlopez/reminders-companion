import EventKit
import Foundation

/// Creates a self-contained demo list so someone trying the app for the first time has
/// something to drag around.
///
/// Everything lands in one clearly named list that can be removed in a single action, and
/// no existing list or reminder is read, modified or touched in any way. The spread is
/// chosen to exercise every part of the board at once: undated items for the Unscheduled
/// pool, a span, a backlog item, priorities, and one timed reminder with an alarm so the
/// "notifications are never altered" behaviour is visible.
extension ReminderStore {

    public static let sampleListName = "Companion Demo"

    public var hasSampleData: Bool {
        lists.contains { $0.title == Self.sampleListName }
    }

    private struct Sample {
        var title: String
        /// Planned day, relative to today.
        var startOffset: Int?
        /// Deadline, relative to today.
        var dueOffset: Int?
        var priority: Priority = .none
        /// Adds a 9:00 AM deadline plus a matching alarm, like a bill.
        var timedWithAlarm = false
    }

    private static let samples: [Sample] = [
        // Unscheduled — the pool you plan a week from.
        Sample(title: "Draft the Q4 proposal", startOffset: nil, dueOffset: nil),
        Sample(title: "Order replacement cables", startOffset: nil, dueOffset: nil),
        Sample(title: "Write up the studio notes", startOffset: nil, dueOffset: nil, priority: .low),
        Sample(title: "Research new invoicing tool", startOffset: nil, dueOffset: nil),

        // Today.
        Sample(title: "Call the venue back", startOffset: 0, dueOffset: nil, priority: .high),
        Sample(title: "Send over the revised quote", startOffset: 0, dueOffset: nil),

        // Later this week.
        Sample(title: "Site walkthrough", startOffset: 2, dueOffset: nil, priority: .medium),
        Sample(title: "Edit the highlight reel", startOffset: 3, dueOffset: nil),

        // A genuine multi-day span: planned today, owed in three days.
        Sample(title: "Build the client deck", startOffset: 0, dueOffset: 3, priority: .high),

        // Backlog — slipped past the whole of last week.
        Sample(title: "Chase the outstanding invoice", startOffset: nil, dueOffset: -12, priority: .high),
        Sample(title: "Return the rental lens", startOffset: nil, dueOffset: -9),

        // A bill: timed deadline with a real alarm, to show scheduling never disturbs it.
        Sample(title: "Pay the studio insurance", startOffset: nil, dueOffset: 4, timedWithAlarm: true),
    ]

    /// Creates the demo list and its tasks. Safe to call twice — it reuses the list.
    public func installSampleData() async {
        guard access == .granted else { return }

        let calendar: EKCalendar
        if let existing = store.calendars(for: .reminder)
            .first(where: { $0.title == Self.sampleListName }) {
            calendar = existing
        } else {
            let created = EKCalendar(for: .reminder, eventStore: store)
            created.title = Self.sampleListName
            // Match the default list's account so the demo syncs like everything else.
            created.source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first { $0.sourceType == .calDAV }
                ?? store.sources.first { $0.sourceType == .local }
            do {
                try store.saveCalendar(created, commit: true)
            } catch {
                lastError = "Could not create the demo list: \(error.localizedDescription)"
                return
            }
            calendar = created
        }

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let today = Day.today()

        for sample in Self.samples {
            let reminder = EKReminder(eventStore: store)
            reminder.title = sample.title
            reminder.calendar = calendar
            reminder.priority = sample.priority.rawValue

            if sample.timedWithAlarm, let offset = sample.dueOffset {
                var due = DateComponents()
                due.calendar = Day.gregorian
                due.timeZone = .current
                let day = today.adding(days: offset)
                due.year = day.year; due.month = day.month; due.day = day.day
                due.hour = 9; due.minute = 0; due.second = 0
                reminder.dueDateComponents = due
                if let fireDate = gregorian.date(from: due) {
                    reminder.addAlarm(EKAlarm(absoluteDate: fireDate))
                }
            } else {
                if let offset = sample.dueOffset {
                    reminder.dueDateComponents = Scheduling.deadlineComponents(
                        for: today.adding(days: offset), preserving: nil
                    )
                }
                if let offset = sample.startOffset {
                    reminder.startDateComponents = Scheduling.plannedComponents(
                        for: today.adding(days: offset), alongside: reminder.dueDateComponents
                    )
                }
            }

            try? store.save(reminder, commit: false)
        }

        do {
            markLocalWrite()
            try store.commit()
        } catch {
            lastError = "Could not add the demo tasks: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Deletes the demo list and everything in it. Touches nothing else.
    public func removeSampleData() async {
        guard let calendar = store.calendars(for: .reminder)
            .first(where: { $0.title == Self.sampleListName }) else { return }
        do {
            markLocalWrite()
            try store.removeCalendar(calendar, commit: true)
        } catch {
            lastError = "Could not remove the demo list: \(error.localizedDescription)"
        }
        await refresh()
    }
}
