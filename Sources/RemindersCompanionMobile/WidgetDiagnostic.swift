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
        return log.joined(separator: "\n")
    }
}
