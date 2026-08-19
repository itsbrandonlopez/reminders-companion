#if DEBUG && !os(watchOS)
import EventKit
import Foundation

/// Answers the one question left open about this app: does completing a repeating
/// reminder through EventKit roll the series forward the way Reminders' own UI does?
///
/// If it does not, ticking a repeating task here would silently end the series — the only
/// remaining way this app could damage real data. Written as a diagnostic rather than a
/// unit test because it needs a live EventKit store; run it against a Simulator, whose
/// Reminders database is disposable.
extension ReminderStore {

    public static let recurrenceTestListName = "RC Recurrence Test"

    public func diagnoseRecurringCompletion() async -> String {
        var log: [String] = ["── Recurring completion diagnostic ──"]
        guard access == .granted else { return "✗ no Reminders access" }

        // A dedicated list, so nothing real is ever involved.
        let calendar: EKCalendar
        if let existing = store.calendars(for: .reminder)
            .first(where: { $0.title == Self.recurrenceTestListName }) {
            calendar = existing
        } else {
            let made = EKCalendar(for: .reminder, eventStore: store)
            made.title = Self.recurrenceTestListName
            made.source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first { $0.sourceType == .local }
            do { try store.saveCalendar(made, commit: true) } catch {
                return "✗ could not create test list: \(error.localizedDescription)"
            }
            calendar = made
        }

        let title = "Repeating probe \(UUID().uuidString.prefix(6))"
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let today = Day.today()
        reminder.dueDateComponents = Scheduling.deadlineComponents(for: today, preserving: nil)
        satisfyStartDateRequirement(on: reminder)
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))

        do { try store.save(reminder, commit: true) } catch {
            return "✗ could not save the repeating reminder: \(error.localizedDescription)"
        }

        let externalID = reminder.calendarItemExternalIdentifier ?? ""
        log.append("  created: \(title)")
        log.append("  due before   : \(Day(reminder.dueDateComponents)?.description ?? "—")")
        log.append("  recurrence   : \(reminder.recurrenceRules?.count ?? 0) rule(s)")
        log.append("  externalID   : \(externalID)")

        // Complete it exactly as the app's checkbox does.
        guard let live = store.calendarItems(withExternalIdentifier: externalID)
            .compactMap({ $0 as? EKReminder }).first else {
            return (log + ["✗ could not resolve the reminder to complete it"]).joined(separator: "\n")
        }
        live.isCompleted = true
        do { try store.save(live, commit: true) } catch {
            return (log + ["✗ completing failed: \(error.localizedDescription)"]).joined(separator: "\n")
        }
        log.append("  completed via EventKit")

        // Re-read from a fresh store: did the series survive?
        let verify = EKEventStore()
        guard (try? await verify.requestFullAccessToReminders()) == true else {
            return (log + ["✗ verify store denied"]).joined(separator: "\n")
        }
        guard let vList = verify.calendars(for: .reminder)
            .first(where: { $0.title == Self.recurrenceTestListName }) else {
            return (log + ["✗ test list vanished"]).joined(separator: "\n")
        }

        // `EKReminder` is not Sendable and EventKit calls back on its own queue, so the
        // results cross the isolation boundary boxed, as in `ReminderStore.fetch`.
        struct Boxed<T>: @unchecked Sendable { let value: T }
        let boxed: Boxed<[EKReminder]> = await withCheckedContinuation { cont in
            verify.fetchReminders(
                matching: verify.predicateForIncompleteReminders(
                    withDueDateStarting: nil, ending: nil, calendars: [vList]
                )
            ) { cont.resume(returning: Boxed(value: $0 ?? [])) }
        }
        let incomplete = boxed.value
        let survivor = incomplete.first { $0.title == title }

        log.append("")
        log.append("  ▸ AFTER COMPLETING")
        log.append("    incomplete occurrences remaining: \(incomplete.filter { $0.title == title }.count)")
        if let survivor {
            log.append("    next due     : \(Day(survivor.dueDateComponents)?.description ?? "—")")
            log.append("    recurrence   : \(survivor.recurrenceRules?.count ?? 0) rule(s)")
            log.append("    still completed? \(survivor.isCompleted)")
        }

        log.append("")
        log.append("  ▸ VERDICT")
        if let survivor, Day(survivor.dueDateComponents) ?? today > today {
            log.append("    ✓ SAFE — the series rolled forward to a later date.")
        } else if survivor != nil {
            log.append("    ⚠ AMBIGUOUS — an incomplete occurrence remains but the due date did not advance.")
        } else {
            log.append("    ✗ UNSAFE — completing ended the series. Repeating tasks must be")
            log.append("      completed in Reminders, and the app should say so.")
        }
        return log.joined(separator: "\n")
    }

    public func removeRecurrenceTestList() async {
        guard let cal = store.calendars(for: .reminder)
            .first(where: { $0.title == Self.recurrenceTestListName }) else { return }
        try? store.removeCalendar(cal, commit: true)
        await refresh()
    }
}
#endif
