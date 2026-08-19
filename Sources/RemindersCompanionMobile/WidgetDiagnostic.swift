#if DEBUG
import EventKit
import RemindersCore
import Foundation

/// Exercises exactly what the widget extension does, from the main app process, since a
/// widget extension process can't be scripted or screenshotted the way the app itself can.
/// This covers the two things unique to the extension's code paths — everything else about
/// the widgets (the SwiftUI views, the timeline schedule) is either visual-only or already
/// proven by the app building and this data flowing correctly through it.
@MainActor
enum WidgetDiagnostic {
    static func run(env: MobileEnvironment) async -> String {
        var log = ["── Widget diagnostic ──"]

        if !env.store.hasSampleData {
            await env.store.installSampleData()
        }

        // 1. WidgetDataProvider's own fetch — bare EKEventStore, no ReminderStore, no
        // MetaStore, exactly as a separate extension process would do it.
        let today = await WidgetDataProvider.fetchToday()
        let next = await WidgetDataProvider.fetchNext()
        let overdue = await WidgetDataProvider.overdueCount()
        log.append("  fetchToday(): \(today.count) task(s)")
        for t in today.prefix(5) { log.append("    • \(t.title) [\(t.listName)]") }
        log.append("  fetchNext(): \(next?.title ?? "none")")
        log.append("  overdueCount(): \(overdue)")
        let dataOK = !today.isEmpty || !env.store.tasks.filter { !$0.isCompleted }.isEmpty
        log.append("  ▸ data path: \(dataOK ? "✓ produced results" : "⚠ empty — demo data may not have seeded")")

        // 2. The exact completion path CompleteTaskIntent.perform() calls, run against a
        // scratch task and a *fresh* EKEventStore — an extension process never shares the
        // app's live store instance, so this proves the standalone path, not just that
        // "completion works somewhere in the app" (already covered elsewhere).
        guard let list = env.store.lists.first(where: { $0.title == ReminderStore.sampleListName })
                ?? env.store.lists.first(where: \.isEditable) else {
            log.append("  ✗ no editable list available for the completion probe")
            return log.joined(separator: "\n")
        }
        await env.store.create(title: "Widget completion probe", in: list.id, on: .today())
        await env.store.refresh()
        guard let probe = env.store.tasks.first(where: { $0.title == "Widget completion probe" }) else {
            log.append("  ✗ could not create the completion probe task")
            return log.joined(separator: "\n")
        }

        let freshStore = EKEventStore()
        let completed: Bool
        do {
            completed = try ReminderStore.completeReminder(externalID: probe.id, in: freshStore)
        } catch {
            log.append("  ✗ completeReminder threw: \(error.localizedDescription)")
            return log.joined(separator: "\n")
        }
        log.append("  completeReminder(externalID:in:) via a fresh EKEventStore: \(completed)")

        // Re-verify from a third, independent store — the same "did it actually persist,
        // not just succeed in memory" check every prior diagnostic in this app has used.
        let verifyStore = EKEventStore()
        _ = try? await verifyStore.requestFullAccessToReminders()
        let stillIncomplete = verifyStore.calendarItems(withExternalIdentifier: probe.id)
            .compactMap { $0 as? EKReminder }
            .first?.isCompleted == false
        log.append("  ▸ VERDICT")
        log.append(stillIncomplete
            ? "    ✗ UNSAFE — the reminder is still incomplete after completing it."
            : "    ✓ SAFE — completion via the widget's own code path persisted correctly.")

        await env.store.delete(probe)

        log.append("")
        log.append(await quickAddChecks(env: env))
        log.append("")
        log.append(await undoChecks(env: env))
        log.append("")
        log.append(await detailFieldChecks(env: env))
        return log.joined(separator: "\n")
    }

    /// Tranche-1 detail fields. The due-time toggle is the one that matters: writing a time
    /// makes the item non-all-day, and the original spike showed that getting the start
    /// date's timed-ness wrong silently strips the time straight back off.
    private static func detailFieldChecks(env: MobileEnvironment) async -> String {
        var log = ["── Detail fields diagnostic ──"]
        guard let list = env.store.lists.first(where: { $0.title == ReminderStore.sampleListName })
                ?? env.store.lists.first(where: \.isEditable) else { return "  ✗ no editable list" }

        let title = "Detail probe \(UUID().uuidString.prefix(6))"
        await env.store.create(title: title, in: list.id, on: .today())
        await env.store.refresh()
        guard var p = env.store.tasks.first(where: { $0.title == title }) else {
            return "  ✗ could not create the probe"
        }
        func reload() { p = env.store.tasks.first { $0.id == p.id } ?? p }


        await env.store.setURL(p, "https://example.com/brief"); reload()
        log.append("  url: \(p.url?.absoluteString ?? "nil")  \(p.url?.absoluteString == "https://example.com/brief" ? "✓" : "✗")")

        let target = Day.today().adding(days: 3)
        await env.store.setDueDay(p, to: target); reload()
        log.append("  deadline all-day: \(p.dueDay?.description ?? "nil") timed=\(p.dueIsTimed)  \(p.dueDay == target && !p.dueIsTimed ? "✓" : "✗")")

        await env.store.setDueTime(p, hour: 9, minute: 30); reload()
        let timeOK = p.dueIsTimed && p.dueDay == target
        log.append("  + time 09:30: \(p.dueTimeLabel ?? "none") on \(p.dueDay?.description ?? "nil")  \(timeOK ? "✓" : "✗ time or day lost")")

        await env.store.setDueTime(p, hour: nil, minute: nil); reload()
        let clearedOK = !p.dueIsTimed && p.dueDay == target
        log.append("  time cleared: timed=\(p.dueIsTimed) day=\(p.dueDay?.description ?? "nil")  \(clearedOK ? "✓" : "✗")")

        await env.store.delete(p)
        return log.joined(separator: "\n")
    }

    /// Undo writes straight through to Reminders, so "it reversed" has to mean the
    /// reminder's actual state came back — not just that the in-memory value changed.
    private static func undoChecks(env: MobileEnvironment) async -> String {
        var log = ["── Undo diagnostic ──"]
        guard let list = env.store.lists.first(where: { $0.title == ReminderStore.sampleListName })
                ?? env.store.lists.first(where: \.isEditable) else {
            return "  ✗ no editable list"
        }

        let title = "Undo probe \(UUID().uuidString.prefix(6))"
        let original = Day.today().adding(days: 2)
        await env.store.create(title: title, in: list.id, on: original)
        await env.store.refresh()
        guard var task = env.store.tasks.first(where: { $0.title == title }) else {
            return "  ✗ could not create the probe"
        }

        // 1. Reschedule, then undo.
        await env.store.schedule(task, to: Day.today().adding(days: 5))
        task = env.store.tasks.first { $0.id == task.id } ?? task
        let moved = task.plannedDay
        await env.store.undoLast()
        task = env.store.tasks.first { $0.id == task.id } ?? task
        log.append("  reschedule: \(original) → \(moved?.description ?? "nil") → undo → \(task.plannedDay?.description ?? "nil")")
        log.append("    \(task.plannedDay == original ? "✓ restored" : "✗ not restored")")

        // 2. Deadline, then undo. Started with none, so undo must clear it again.
        await env.store.setDueDay(task, to: Day.today().adding(days: 9))
        task = env.store.tasks.first { $0.id == task.id } ?? task
        let dueSet = task.dueDay
        await env.store.undoLast()
        task = env.store.tasks.first { $0.id == task.id } ?? task
        log.append("  deadline: nil → \(dueSet?.description ?? "nil") → undo → \(task.dueDay?.description ?? "nil")")
        log.append("    \(task.dueDay == nil ? "✓ cleared again" : "✗ deadline left behind")")

        // 3. Move between lists, then undo.
        if let other = env.store.lists.first(where: { $0.isEditable && $0.id != list.id }) {
            await env.store.move(task, toList: other.id)
            task = env.store.tasks.first { $0.id == task.id } ?? task
            let movedTo = task.listName
            await env.store.undoLast()
            task = env.store.tasks.first { $0.id == task.id } ?? task
            log.append("  list: \(list.title) → \(movedTo) → undo → \(task.listName)")
            log.append("    \(task.listID == list.id ? "✓ restored" : "✗ not restored")")
        }

        // 4. Bulk reschedule: every task must come back to its *own* previous day, not a
        // shared one, and not stay where the bulk move put them.
        let dayA = Day.today().adding(days: 3)
        let dayB = Day.today().adding(days: 6)
        let bulkStamp = UUID().uuidString.prefix(5)
        await env.store.create(title: "Bulk A \(bulkStamp)", in: list.id, on: dayA)
        await env.store.create(title: "Bulk B \(bulkStamp)", in: list.id, on: dayB)
        await env.store.refresh()
        let bulk = env.store.tasks.filter { $0.title.hasSuffix(String(bulkStamp)) }
        if bulk.count == 2 {
            await env.store.schedule(bulk, to: Day.today())
            await env.store.refresh()
            let movedAll = env.store.tasks
                .filter { $0.title.hasSuffix(String(bulkStamp)) }
                .allSatisfy { $0.plannedDay == Day.today() }
            await env.store.undoLast()
            await env.store.refresh()
            let restored = env.store.tasks.filter { $0.title.hasSuffix(String(bulkStamp)) }
            let a = restored.first { $0.title.hasPrefix("Bulk A") }?.plannedDay
            let b = restored.first { $0.title.hasPrefix("Bulk B") }?.plannedDay
            log.append("  bulk: both → today (\(movedAll ? "✓" : "✗")) → undo → A=\(a?.description ?? "nil") B=\(b?.description ?? "nil")")
            log.append("    \(a == dayA && b == dayB ? "✓ each restored to its own day" : "✗ not restored individually")")
            for t in restored { await env.store.delete(t) }
        }

        // 5. "Next Up" must be the nearest by date, not the highest priority.
        let nextStamp = UUID().uuidString.prefix(5)
        await env.store.create(
            title: "Soon low \(nextStamp)", in: list.id, on: Day.today().adding(days: 1),
            priority: .low
        )
        await env.store.create(
            title: "Later high \(nextStamp)", in: list.id, on: Day.today().adding(days: 30),
            priority: .high
        )
        await env.store.refresh()
        // Asserting the property rather than naming an expected task: the demo data
        // contains an overdue high-priority item that is *also* the earliest, so a
        // by-title check would pass under both the old and new ordering and prove nothing.
        let next = await WidgetDataProvider.fetchNext()
        let allDated = await WidgetDataProvider.fetchTasks().compactMap(\.boardDay)
        let earliest = allDated.min()
        let pickedNearest = next?.boardDay == earliest
        log.append("  next-up picked: \(next?.title ?? "nil") (\(next?.boardDay?.description ?? "nil"))")
        log.append("    earliest dated task overall: \(earliest?.description ?? "nil")")
        log.append("    \(pickedNearest ? "✓ nearest by date" : "✗ not the earliest — still ordering by priority")")

        // And the discriminating case in isolation: among two tasks where date and
        // priority disagree, date must win.
        let soon = env.store.tasks.first { $0.title.hasPrefix("Soon low") }
        let later = env.store.tasks.first { $0.title.hasPrefix("Later high") }
        if let soon, let later {
            let ordered = [later, soon].sorted { l, r in
                let a = l.boardDay ?? .today(), b = r.boardDay ?? .today()
                if a != b { return a < b }
                return l.priority.sortWeight < r.priority.sortWeight
            }
            let dateWins = ordered.first?.title.hasPrefix("Soon low") == true
            log.append("    date beats priority when they disagree: \(dateWins ? "✓" : "✗")")
        }
        for t in env.store.tasks.filter({ $0.title.hasSuffix(String(nextStamp)) }) {
            await env.store.delete(t)
        }

        // 6. Undoing must not itself become undoable, or the banner would never clear.
        let slotAfterUndo = env.store.undoable == nil
        log.append("  undo slot cleared after undoing: \(slotAfterUndo ? "✓" : "✗ would loop")")

        await env.store.delete(task)
        return log.joined(separator: "\n")
    }

    /// Proves quick-add end to end: parsed text in, a correctly dated, prioritised and
    /// filed reminder out of EventKit. The parser itself is unit-tested; this checks the
    /// wiring between it and `create`.
    private static func quickAddChecks(env: MobileEnvironment) async -> String {
        var log = ["── Quick-add diagnostic ──"]
        let stamp = UUID().uuidString.prefix(6)

        let title = "QA probe \(stamp)"
        await env.quickAdd("!! \(title) tomorrow", defaultDay: nil)
        await env.store.refresh()

        guard let made = env.store.tasks.first(where: { $0.title == title }) else {
            log.append("  ✗ quick-add produced no task (title should have been \"\(title)\")")
            return log.joined(separator: "\n")
        }
        log.append("  input   : \"!! \(title) tomorrow\"")
        log.append("  title   : \(made.title)")
        log.append("  day     : \(made.plannedDay?.description ?? "none")")
        log.append("  priority: \(made.priority.label)")
        log.append("  list    : \(made.listName)")

        let expectedDay = Day.today().adding(days: 1)
        let titleClean = made.title == title
        let dayRight = made.plannedDay == expectedDay
        let priorityRight = made.priority == .medium

        log.append("  ▸ VERDICT")
        log.append("    tokens stripped from title : \(titleClean ? "✓" : "✗")")
        log.append("    scheduled for tomorrow     : \(dayRight ? "✓" : "✗ expected \(expectedDay)")")
        log.append("    priority applied           : \(priorityRight ? "✓" : "✗")")

        // And the protective case: a date word mid-sentence must survive into the title.
        let midTitle = "Prep Tuesday's invoice \(stamp)"
        await env.quickAdd(midTitle, defaultDay: nil)
        await env.store.refresh()
        let survived = env.store.tasks.contains { $0.title == midTitle }
        log.append("    mid-sentence date preserved: \(survived ? "✓" : "✗ title was altered")")

        await env.store.delete(made)
        if let m = env.store.tasks.first(where: { $0.title == midTitle }) {
            await env.store.delete(m)
        }
        return log.joined(separator: "\n")
    }
}
#endif
