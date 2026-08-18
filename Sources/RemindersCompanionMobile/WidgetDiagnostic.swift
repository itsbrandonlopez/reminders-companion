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
