import EventKit
import RemindersCore
import Foundation

/// The widget's own read path.
///
/// Deliberately not `RemindersCore.ReminderStore`. A widget extension is a separate,
/// short-lived, memory-constrained process — pulling in `ReminderStore`'s SwiftData
/// sidecar for information the widget never shows (manual rank, estimates, folders) would
/// spend that budget for nothing. This talks to `EKEventStore` directly and reuses
/// `ReminderStore.makeTaskItem`, so the widget builds the exact same `TaskItem` shape the
/// app does from the exact same mapping — just without the sidecar underneath it.
public enum WidgetDataProvider {

    public static func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Everything incomplete, mapped and sorted the same way `MobileEnvironment.tasks`
    /// does: priority first, then day. Neutral rank (0) throughout, since the widget has
    /// no manual ordering to honour — the phone app itself doesn't either.
    public static func fetchTasks() async -> [TaskItem] {
        guard authorizationStatus() == .fullAccess else { return [] }
        let store = EKEventStore()

        struct Boxed<T>: @unchecked Sendable { let value: T }
        let boxed: Boxed<[EKReminder]> = await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
            store.fetchReminders(matching: predicate) {
                continuation.resume(returning: Boxed(value: $0 ?? []))
            }
        }

        return boxed.value
            .compactMap { ReminderStore.makeTaskItem(from: $0, rank: 0, estimateMinutes: nil) }
            .sorted { lhs, rhs in
                if lhs.priority.sortWeight != rhs.priority.sortWeight {
                    return lhs.priority.sortWeight < rhs.priority.sortWeight
                }
                return (lhs.boardDay ?? .today()) < (rhs.boardDay ?? .today())
            }
    }

    /// Today's dated work — planned, due, or overdue — same rule as the phone app's Today
    /// tab and widget's own "Today" kind.
    public static func fetchToday() async -> [TaskItem] {
        let today = Day.today()
        return await fetchTasks().filter { task in
            guard let span = task.span else { return false }
            return span.contains(today) || task.isOverdue()
        }
    }

    /// The single next dated task, for the "Next Up" widget.
    public static func fetchNext() async -> TaskItem? {
        await fetchTasks().first { $0.boardDay != nil }
    }

    public static func overdueCount() async -> Int {
        await fetchTasks().filter { $0.isOverdue() }.count
    }
}
