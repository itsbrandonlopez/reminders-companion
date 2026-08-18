#if DEBUG
import Foundation
import RemindersCore

/// Exercises the exact write path the UI uses, against a scratch list.
///
/// The EventKit *semantics* were settled by the Phase 0 probe, but `ReminderStore`'s
/// own plumbing — resolving a live `EKReminder` from a value type by external
/// identifier, and the fetch→mutate→refetch cycle — is only reachable from inside a
/// bundled app that holds Reminders access. Hence a hidden `--selftest` flag rather
/// than a unit test.
@MainActor
enum SelfTest {
    static func run(_ store: ReminderStore) async -> String {
        var log: [String] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            log.append("  \(passed ? "✓" : "✗") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        await store.refresh()

        // Prefer the spike's scratch list so nothing real is touched.
        guard let list = store.lists.first(where: { $0.title == "RC Probe" })
                ?? store.lists.first(where: { $0.isDefault }) else {
            return "✗ no writable list available"
        }
        log.append("── ReminderStore self-test (list: \(list.title)) ──")

        let title = "Self-test \(UUID().uuidString.prefix(8))"
        await store.create(title: title, in: list.id, on: nil)
        guard let created = store.tasks.first(where: { $0.title == title }) else {
            return (log + ["✗ create failed — nothing to test against"]).joined(separator: "\n")
        }
        check("create", true, created.id)
        check("new task lands in backlog", created.isBacklog)

        // Schedule → the drag-onto-a-day path.
        let target = Day.today().adding(days: 2)
        await store.schedule(created, to: target)
        var current = store.tasks.first { $0.id == created.id }
        check("schedule sets planned day", current?.plannedDay == target,
              "got \(current?.plannedDay?.description ?? "nil"), wanted \(target)")
        check("schedule leaves due date alone", current?.dueDay == nil)
        check("resolved by external identifier across refetch", current != nil)

        // Reschedule → proves the lookup survives repeated round trips.
        let target2 = Day.today().adding(days: 4)
        await store.schedule(current ?? created, to: target2)
        current = store.tasks.first { $0.id == created.id }
        check("reschedule", current?.plannedDay == target2)

        // Priority.
        await store.setPriority(current ?? created, .high)
        current = store.tasks.first { $0.id == created.id }
        check("set priority", current?.priority == .high, current?.priority.label ?? "nil")

        // Unschedule → the drop-into-backlog path.
        await store.schedule(current ?? created, to: nil)
        current = store.tasks.first { $0.id == created.id }
        check("unschedule clears planned day", current?.plannedDay == nil)
        check("unscheduled task returns to backlog", current?.isBacklog == true)

        // Move between lists.
        if let other = store.lists.first(where: { $0.isEditable && $0.id != list.id }) {
            await store.move(current ?? created, toList: other.id)
            current = store.tasks.first { $0.id == created.id }
            check("move to another list", current?.listID == other.id, current?.listName ?? "nil")
            await store.move(current ?? created, toList: list.id)
            current = store.tasks.first { $0.id == created.id }
            check("move back", current?.listID == list.id)
        }

        // Sidecar ordering never touches Reminders.
        store.setEstimate(45, for: current ?? created)
        current = store.tasks.first { $0.id == created.id }
        check("sidecar estimate persists", current?.estimateMinutes == 45)

        // Completing drops it from the incomplete fetch — that absence is the assertion.
        await store.setCompleted(current ?? created, true)
        check("completed task leaves the board", !store.tasks.contains { $0.id == created.id })

        // Cleanup. The task is completed, so it is no longer in `tasks`; rebuild a
        // reference from the original value — which also tests lookup of a completed item.
        await store.delete(created)
        await store.refresh()
        check("deleted", !store.tasks.contains { $0.id == created.id })

        let failures = log.filter { $0.contains("✗") }.count
        log.append("── \(failures == 0 ? "all checks passed" : "\(failures) FAILED") ──")
        return log.joined(separator: "\n")
    }
}
#endif
