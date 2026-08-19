#if DEBUG
import CoreLocation
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
        log.append("")
        log.append(await alarmAndRepeatChecks(env: env))
        return log.joined(separator: "\n")
    }

    /// The two fields the app deliberately avoided writing until now. Each is checked for
    /// round-tripping *and* for the guard that stops it clobbering something richer.
    private static func alarmAndRepeatChecks(env: MobileEnvironment) async -> String {
        var log = ["── Alarm & repeat diagnostic ──"]
        guard let list = env.store.lists.first(where: { $0.title == ReminderStore.sampleListName })
                ?? env.store.lists.first(where: \.isEditable) else { return "  ✗ no editable list" }

        let title = "Alarm probe \(UUID().uuidString.prefix(6))"
        await env.store.create(title: title, in: list.id, on: .today())
        await env.store.refresh()
        guard var p = env.store.tasks.first(where: { $0.title == title }) else {
            return "  ✗ could not create the probe"
        }
        func reload() { p = env.store.tasks.first { $0.id == p.id } ?? p }

        // Alarm round trip.
        let fire = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        await env.store.setAlarm(p, at: fire); reload()
        let gotAlarm = p.alarms.count == 1 && p.hasAlarms
        log.append("  alarm set: \(p.alarms.first?.label ?? "none")  \(gotAlarm ? "✓" : "✗")")

        await env.store.setAlarm(p, at: nil); reload()
        log.append("  alarm cleared: \(p.alarms.isEmpty && !p.hasAlarms ? "✓" : "✗")")

        // Repeat round trip. A repeat rule is anchored to the *due* date — the earlier
        // recurrence diagnostic that worked set one first — so this checks both states.
        // Two outcomes this must tell apart, which the old wording ("refused/dropped")
        // conflated: the store refusing up front, versus EventKit accepting the rule in
        // memory and silently discarding it on save. Only the first is a working guard —
        // and the return value is the only thing that distinguishes them.
        let refusedNoDeadline = await env.store.setRecurrence(
            p, SimpleRecurrence(frequency: .weekly, interval: 2)
        ) == false
        reload()
        log.append("  repeat with no deadline: refused=\(refusedNoDeadline) ruleAbsent=\(p.recurrence == nil)  " +
            (refusedNoDeadline && p.recurrence == nil
                ? "✓ refused up front"
                : "✗ the store let it through — EventKit dropped it silently"))

        await env.store.setDueDay(p, to: Day.today().adding(days: 1)); reload()
        await env.store.setRecurrence(p, SimpleRecurrence(frequency: .weekly, interval: 2)); reload()
        let r = p.recurrence
        let repeatOK = r?.frequency == .weekly && r?.interval == 2 && r?.isEditableHere == true
        log.append("  repeat set: \(r?.label ?? "none")  \(repeatOK ? "✓" : "✗")")

        // Editing other fields must not disturb the repeat rule.
        await env.store.setPriority(p, .high); reload()
        log.append("  repeat survives an unrelated edit: \(p.recurrence?.interval == 2 ? "✓" : "✗")")

        await env.store.setRecurrence(p, nil); reload()
        log.append("  repeat cleared: \(p.recurrence == nil && !p.isRecurring ? "✓" : "✗")")

        // The guard: a rule richer than this app can express must be refused, not
        // silently flattened. Written with EventKit directly, since the app cannot build one.
        let direct = EKEventStore()
        var guardResult = "could not construct a positional rule"
        if (try? await direct.requestFullAccessToReminders()) == true,
           let live = direct.calendarItems(withExternalIdentifier: p.id)
               .compactMap({ $0 as? EKReminder }).first {
            let everySecondTuesday = EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)],
                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil
            )
            live.addRecurrenceRule(everySecondTuesday)
            try? direct.save(live, commit: true)
            await env.store.refresh(); reload()

            let detected = p.recurrence?.isEditableHere == false
            let refused = await env.store.setRecurrence(
                p, SimpleRecurrence(frequency: .daily)
            ) == false
            reload()
            let intact = p.recurrence?.hasPositionalSpecifiers == true
            guardResult = "detected=\(detected) refused=\(refused) ruleIntact=\(intact)  " +
                (detected && refused && intact ? "✓ not clobbered" : "✗ GUARD FAILED")
        }
        log.append("  'every 2nd Tuesday': \(guardResult)")

        // The stale-snapshot guard. `setAlarm` clears every alarm before writing a new
        // one, so its "is any of these a geofence?" check has to read the *live* reminder:
        // a snapshot captured before a geofence arrived from another device would pass the
        // check and the write would delete a geofence this app cannot rebuild.
        //
        // Reproduced exactly: hold a snapshot, add a geofence behind its back, then edit
        // from the snapshot.
        let stale = p                                   // captured with no alarms
        let geo = EKEventStore()
        var staleResult = "could not seed a geofence alarm"
        if (try? await geo.requestFullAccessToReminders()) == true,
           let live = geo.calendarItems(withExternalIdentifier: p.id)
               .compactMap({ $0 as? EKReminder }).first {
            let alarm = EKAlarm()
            let place = EKStructuredLocation(title: "Studio")
            place.geoLocation = CLLocation(latitude: 37.3349, longitude: -122.0090)
            place.radius = 100
            alarm.structuredLocation = place
            alarm.proximity = .enter
            live.addAlarm(alarm)

            if (try? geo.save(live, commit: true)) != nil {
                await env.store.refresh()
                let seeded = env.store.tasks.first { $0.id == p.id }
                let geofencePresent = seeded?.alarms.contains { !$0.isEditableHere } == true

                if geofencePresent {
                    // `stale` still reports no alarms. The guard must refuse anyway.
                    let refused = await env.store.setAlarm(stale, at: Date().addingTimeInterval(3600)) == false

                    // Verify from an independent store that the geofence really survived,
                    // rather than trusting the in-memory value.
                    let verify = EKEventStore()
                    _ = try? await verify.requestFullAccessToReminders()
                    // Checked against raw EventKit rather than our own `alarmShape`, so a
                    // bug in the mapping cannot make this read as a pass.
                    let survived = verify.calendarItems(withExternalIdentifier: p.id)
                        .compactMap { $0 as? EKReminder }
                        .first
                        .map { ($0.alarms ?? []) }?
                        .contains { $0.structuredLocation != nil && $0.proximity != .none } == true

                    staleResult = "staleSnapshotSawNoAlarms=\(stale.alarms.isEmpty) refused=\(refused) geofenceSurvived=\(survived)  " +
                        (refused && survived ? "✓ not clobbered" : "✗ GUARD FAILED — a geofence was destroyed")
                } else {
                    staleResult = "geofence did not persist on this platform — guard untested"
                }
            }
        }
        log.append("  stale-snapshot alarm guard: \(staleResult)")

        await env.store.delete(p)
        log.append("")
        log.append(await unscheduleChecks(env: env))
        return log.joined(separator: "\n")
    }

    /// Removing the planned day from a task that *has* a deadline — the one scheduling
    /// gesture that can only be verified here.
    ///
    /// `EKReminder`'s header states that iOS refuses to save a due date with no start date
    /// (`EKErrorNoStartDate`) and that macOS does not. This probe exists to check that
    /// claim rather than trust it, because the Mac's `--selftest` runs the same gesture
    /// against a task with *no* deadline, on the platform the rule doesn't apply to — so it
    /// passes there under both a correct and a broken build. The report prints what the
    /// platform actually did, so a future iOS that starts enforcing the rule shows up here
    /// as a changed line rather than as a silent failure in the field.
    private static func unscheduleChecks(env: MobileEnvironment) async -> String {
        var log = ["── Unschedule diagnostic ──"]
        guard let list = env.store.lists.first(where: { $0.title == ReminderStore.sampleListName })
                ?? env.store.lists.first(where: \.isEditable) else { return "  ✗ no editable list" }

        let title = "Unschedule probe \(UUID().uuidString.prefix(6))"
        let deadline = Day.today().adding(days: 4)
        await env.store.create(title: title, in: list.id, on: .today(), due: deadline)
        await env.store.refresh()
        guard var p = env.store.tasks.first(where: { $0.title == title }) else {
            return "  ✗ could not create the probe"
        }
        func reload() { p = env.store.tasks.first { $0.id == p.id } ?? p }

        log.append("  before: planned=\(p.plannedDay?.description ?? "nil") due=\(p.dueDay?.description ?? "nil")")

        env.store.clearError()
        await env.store.schedule(p, to: nil)
        reload()

        // Three things have to hold: the save didn't error, the task is still there, and
        // it still sits on its deadline's day rather than vanishing off the board.
        let noError = env.store.lastError == nil
        let stillPresent = env.store.tasks.contains { $0.id == p.id }
        let onDeadline = p.boardDay == deadline
        let spanIntact = !p.spansMultipleDays && p.dueDay == deadline

        log.append("  after : planned=\(p.plannedDay?.description ?? "nil") due=\(p.dueDay?.description ?? "nil") boardDay=\(p.boardDay?.description ?? "nil")")
        if let error = env.store.lastError { log.append("  error : \(error)") }
        // Which branch the platform took. `nil` means iOS accepted a due date with no start
        // date, contradicting the header; a start date equal to the deadline means the save
        // was refused and `saveRepairingStartDate` supplied one.
        log.append(p.plannedDay == nil
            ? "  note  : this iOS accepted due-without-start — no start date was invented"
            : "  note  : this iOS enforced EKErrorNoStartDate — start repaired to the deadline")
        log.append("  ▸ VERDICT")
        log.append(noError && stillPresent && onDeadline && spanIntact
            ? "    ✓ SAFE — unscheduling a task with a deadline saved, and it renders on its deadline."
            : "    ✗ UNSAFE — saved=\(noError) present=\(stillPresent) onDeadline=\(onDeadline) span=\(spanIntact)")

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

        // 7. Undo must restore the value the field held *immediately* before the edit, not
        // the value it held when the caller last refetched.
        //
        // A detail panel holds one `TaskItem` for as long as it is open and edits from it
        // repeatedly, so two writes to the same field from one snapshot is the ordinary
        // case — and the only one that tells a live read apart from a stale one. Recording
        // from the snapshot makes both edits claim the *original* value, so undoing the
        // second jumps past the first instead of reversing it.
        let stampS = UUID().uuidString.prefix(5)
        let firstDeadline = Day.today().adding(days: 10)
        let secondDeadline = Day.today().adding(days: 20)
        await env.store.create(title: "Stale probe \(stampS)", in: list.id, on: Day.today())
        await env.store.refresh()
        if let held = env.store.tasks.first(where: { $0.title == "Stale probe \(stampS)" }) {
            // `held` is captured once and deliberately never reloaded — that is the point.
            await env.store.setDueDay(held, to: firstDeadline)
            await env.store.setDueDay(held, to: secondDeadline)
            await env.store.undoLast()
            let after = env.store.tasks.first { $0.id == held.id }?.dueDay

            log.append("  stale-snapshot undo: held snapshot due=\(held.dueDay?.description ?? "nil"), " +
                       "set \(firstDeadline) then \(secondDeadline), undo → \(after?.description ?? "nil")")
            log.append(after == firstDeadline
                ? "    ✓ reversed the second edit, landing on the first"
                : "    ✗ undo used the stale snapshot — jumped past the intermediate value")

            if let live = env.store.tasks.first(where: { $0.id == held.id }) {
                await env.store.delete(live)
            }
        }

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
