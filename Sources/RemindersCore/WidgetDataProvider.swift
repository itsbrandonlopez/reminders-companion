import EventKit
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

    /// Requests Reminders access, returning whether it ended up granted.
    ///
    /// A widget extension must never call this — it cannot present a prompt — but the
    /// Watch app must. watchOS apps carry their own TCC grant rather than inheriting the
    /// paired iPhone's, and there is no watchOS Settings pane to grant it after the fact,
    /// so an app that only *checks* the status can leave the user permanently locked out.
    @discardableResult
    public static func requestAccess() async -> Bool {
        switch authorizationStatus() {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await EKEventStore().requestFullAccessToReminders()) ?? false
        default:
            // Denied or restricted: asking again does nothing, the system will not
            // re-prompt.
            return false
        }
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

    /// Today's work, using the *same* rule as the app's Today tab: a task belongs to the
    /// day its `boardDay` names, and anything older is triage rather than today.
    ///
    /// Previously this also swept in every overdue task, which meant the widget's count
    /// and the app's Today tab openly disagreed on the same screen. Overdue work is
    /// surfaced separately, via `overdueCount()`.
    ///
    /// Note that `overdueCount()` is deliberately *not* the number behind the phone app's
    /// backlog banner. That banner counts work which slipped past the whole current week
    /// (`MobileEnvironment.backlogCount`); this counts every deadline already in the past.
    /// A widget is a glance with no room to explain a week-boundary rule, so it answers the
    /// simpler question — but the two are different sets and the labels say so.
    public static func fetchToday() async -> [TaskItem] {
        let today = Day.today()
        return await fetchTasks().filter { $0.boardDay == today }
    }

    /// The next dated task by **date**, for the "Next Up" widget.
    ///
    /// Deliberately re-sorted rather than reusing `fetchTasks()`'s order, which puts
    /// priority first: a high-priority task due next month is not "next up" over a
    /// low-priority one due today. Priority breaks ties on the same day.
    public static func fetchNext() async -> TaskItem? {
        await fetchTasks()
            .filter { $0.boardDay != nil }
            .min { lhs, rhs in
                let l = lhs.boardDay ?? .today()
                let r = rhs.boardDay ?? .today()
                if l != r { return l < r }
                return lhs.priority.sortWeight < rhs.priority.sortWeight
            }
    }

    public static func overdueCount() async -> Int {
        await fetchTasks().filter { $0.isOverdue() }.count
    }

    /// Everything a widget or complication needs, from **one** fetch.
    ///
    /// The granular calls above each build their own `EKEventStore` and run their own
    /// unbounded fetch, so a timeline entry assembled from three of them did the whole job
    /// three times — in a short-lived, memory-capped extension process, which on watchOS is
    /// the tightest budget in the system. Every timeline provider uses this; the granular
    /// calls remain for the diagnostics, which deliberately exercise them in isolation.
    public static func snapshot() async -> Snapshot {
        let all = await fetchTasks()
        let today = Day.today()
        return Snapshot(
            today: all.filter { $0.boardDay == today },
            next: all
                .filter { $0.boardDay != nil }
                .min { lhs, rhs in
                    let l = lhs.boardDay ?? today
                    let r = rhs.boardDay ?? today
                    if l != r { return l < r }
                    return lhs.priority.sortWeight < rhs.priority.sortWeight
                },
            overdueCount: all.filter { $0.isOverdue(asOf: today) }.count
        )
    }

    public struct Snapshot: Sendable {
        /// Today's work, by the same rule as the app's Today tab.
        public let today: [TaskItem]
        /// The nearest dated task by **date**, priority breaking ties on the same day.
        public let next: TaskItem?
        /// Every deadline already in the past — not just the ones falling on today.
        public let overdueCount: Int

        public init(today: [TaskItem], next: TaskItem?, overdueCount: Int) {
            self.today = today
            self.next = next
            self.overdueCount = overdueCount
        }
    }
}
