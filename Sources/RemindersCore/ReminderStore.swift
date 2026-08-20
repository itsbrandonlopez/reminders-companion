import EventKit
import Foundation
import Observation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

public enum AccessState: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case granted
}

/// The only type in the app that touches EventKit.
///
/// Holds one long-lived `EKEventStore` — identifiers and fetched objects are scoped to
/// the store instance that produced them, so sharing one avoids a whole class of
/// cross-store bugs. Everything it publishes is a value type.
@MainActor
@Observable
public final class ReminderStore {
    public private(set) var access: AccessState = .unknown
    public private(set) var lists: [TaskList] = []
    public private(set) var tasks: [TaskItem] = []
    public private(set) var isLoading = false

    /// Bumped whenever `lists` or `tasks` is replaced.
    ///
    /// Lets a view model cache slices derived from them — filtered sets, day buckets,
    /// counts — and know when to rebuild, without comparing whole arrays. Reading it
    /// registers the same observation dependency reading `tasks` would, so a cached
    /// getter still invalidates SwiftUI correctly.
    public private(set) var dataRevision = 0

    /// Calendar access is tracked separately from reminders: it is optional, opt-in, and
    /// its own TCC permission.
    public internal(set) var eventAccess: AccessState = .unknown
    public internal(set) var calendars: [EventCalendar] = []
    public internal(set) var events: [CalendarEvent] = []
    public internal(set) var lastError: String?

    /// One long-lived store shared by reminders and the calendar overlay. Identifiers and
    /// fetched objects are scoped to the instance that produced them, so sharing one
    /// avoids a whole class of cross-store bugs.
    let store = EKEventStore()
    /// The sidecar, when there is one.
    ///
    /// Optional because only the Mac has anything to put in it. The phone shows no manual
    /// ordering and no estimates, so carrying a sidecar there meant reconciling a SwiftData
    /// row per reminder on every refresh — and writing a database to disk — for values
    /// nothing on that platform ever reads.
    private let meta: MetaStore?
    /// `deinit` is nonisolated, so the observer token cannot live on this main-actor
    /// type directly. A tiny box keeps teardown correct under strict concurrency.
    private final class ObserverBox: @unchecked Sendable { var token: NSObjectProtocol? }
    private nonisolated let observerBox = ObserverBox()
    private var refreshTask: Task<Void, Never>?
    /// Every commit we make fires `EKEventStoreChanged` right back at us, and `mutate`
    /// already refreshes explicitly. Without this the app refetches twice per edit.
    private var lastLocalWrite = Date.distantPast
    private static let localWriteEcho: TimeInterval = 1.0

    func markLocalWrite() { lastLocalWrite = .now }

    public init(meta: MetaStore?) {
        self.meta = meta
        self.access = Self.currentState()
        self.eventAccess = Self.eventAccessState()
        observeExternalChanges()
    }

    deinit {
        if let token = observerBox.token { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: - Access

    private static func currentState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .denied, .restricted: .denied
        case .writeOnly: .denied      // useless to us: the app is a reader first
        @unknown default: .unknown
        }
    }

    public func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            access = granted ? .granted : .denied
            if granted { await refresh() }
        } catch {
            lastError = "Could not request Reminders access: \(error.localizedDescription)"
            access = .denied
        }
    }

    /// Sends the user to the one place a declined permission can be restored.
    public func openPrivacySettings() {
        #if canImport(AppKit)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        // iOS has no per-service deep link; this opens the app's own settings page.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
        // watchOS deliberately has no branch: there is no way to open a Settings pane from
        // a watch app, so permission has to be granted on the paired iPhone.
    }

    // MARK: - Change observation

    /// `EKEventStoreChangedNotification` carries no diff — it only says "something moved" —
    /// so the response is always a full refetch. It also arrives in bursts while iCloud
    /// syncs, hence the debounce.
    private func observeExternalChanges() {
        observerBox.token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                // A write this app just made fires its own notification, and `mutate` has
                // already refreshed — so inside the echo window there is usually nothing
                // new to fetch. But this notification is *never redelivered*: dropping it
                // outright also discards a genuine external change that happened to land
                // in the same window (an iCloud push arriving 400ms after you ticked
                // something off), and the app would then show stale data indefinitely.
                //
                // So back off rather than skip. The debounce below collapses the echo and
                // anything riding alongside it into one late refetch — at worst one extra
                // fetch per edit, versus silently missing another device's work.
                let isEcho = Date.now.timeIntervalSince(self.lastLocalWrite) <= Self.localWriteEcho
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: isEcho ? .milliseconds(1200) : .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
    }

    // MARK: - Reading

    /// Bumped by every `refresh`, so a slow one can tell it has been overtaken.
    private var refreshGeneration = 0

    public func refresh() async {
        guard access == .granted else { return }
        // `refresh` is `@MainActor` but not serialized: `await fetch` is a suspension point,
        // so several can be in flight at once — a debounced external change alongside the
        // explicit refresh every `mutate` performs, say. Without a generation, whichever
        // EventKit callback happens to return *last* wins, which is not necessarily the one
        // that started last, and an older snapshot can overwrite a newer one.
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoading = true
        // Only the newest run may clear the spinner; an overtaken one leaving would hide
        // the fact that a fetch is still running.
        defer { if generation == refreshGeneration { isLoading = false } }

        let fetchedLists = store.calendars(for: .reminder).map { calendar in
            TaskList(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: Self.rgba(from: calendar.cgColor),
                isEditable: calendar.allowsContentModifications,
                isDefault: calendar.calendarIdentifier
                    == store.defaultCalendarForNewReminders()?.calendarIdentifier
            )
        }

        // A *bounded* date range silently drops undated reminders, which is where the
        // backlog lives. Fetching everything incomplete and partitioning in memory is
        // both cheaper (one round trip) and the only way to see undated items at all.
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let reminders = await fetch(predicate)

        // Overtaken while waiting on EventKit. Publishing now would put older data on
        // screen than what is already there, and would run the sidecar's garbage collection
        // against a stale set of living ids.
        guard generation == refreshGeneration else { return }

        lists = fetchedLists
        var living = Set<String>()
        var items: [TaskItem] = []
        items.reserveCapacity(reminders.count)

        // One fetch of the sidecar for the whole pass, rather than a predicate fetch per
        // reminder. Nil when there is no sidecar at all — see `meta`.
        var metaIndex = meta?.indexedByExternalID()

        for (position, reminder) in reminders.enumerated() {
            // Seeded so an untouched column reads high-priority-first, while any manual
            // reordering afterwards wins outright.
            let seed = Double(Priority(reminderValue: Int(reminder.priority)).sortWeight) * 1_000_000
                + Double(position) * Ranking.step
            guard let item = makeItem(reminder, fallbackRank: seed, metaIndex: &metaIndex)
            else { continue }
            living.insert(item.id)
            items.append(item)
        }

        if let meta {
            meta.save()
            // `living` holds only *incomplete* reminders, so it is not a list of what still
            // exists — completing a task would otherwise delete its estimate and manual
            // position. Collection is by staleness instead.
            meta.collectGarbage(livingIDs: living)
        }
        tasks = items
        dataRevision &+= 1
    }

    /// `EKReminder` is not `Sendable` and EventKit calls back on its own queue, so the
    /// results cross an isolation boundary in a box. Safe in practice because the array
    /// is handed straight back to this main-actor type and never touched off it.
    private struct Unchecked<T>: @unchecked Sendable {
        let value: T
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        let boxed: Unchecked<[EKReminder]> = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) {
                continuation.resume(returning: Unchecked(value: $0 ?? []))
            }
        }
        return boxed.value
    }

    /// Builds one `TaskItem`, reconciling it against the sidecar index in passing.
    ///
    /// `metaIndex` is `inout` so a row created here is visible to the rest of the pass
    /// without another fetch; nil when the app is running without a sidecar, in which case
    /// the task gets the seeded rank and no estimate — exactly what `WidgetDataProvider`
    /// hands to `makeTaskItem` for the same reason.
    private func makeItem(
        _ reminder: EKReminder, fallbackRank: Double, metaIndex: inout [String: TaskMeta]?
    ) -> TaskItem? {
        guard let id = reminder.calendarItemExternalIdentifier else { return nil }
        guard let meta, metaIndex != nil else {
            return Self.makeTaskItem(from: reminder, rank: fallbackRank, estimateMinutes: nil)
        }
        let row = meta.ensure(
            id, title: reminder.title ?? "", defaultRank: fallbackRank, in: &metaIndex!
        )
        return Self.makeTaskItem(
            from: reminder, rank: row.rank, estimateMinutes: row.estimateMinutes,
            sectionID: row.sectionID
        )
    }

    /// Completes a reminder by external identifier against a bare `EKEventStore`, with no
    /// sidecar, no `@MainActor` isolation and no `ReminderStore` instance required.
    ///
    /// This is the exact path the widget's tap-to-complete `AppIntent` calls — a widget
    /// extension is a separate, short-lived process with its own store, not a shared
    /// instance of the app's `ReminderStore`. Kept as one static function so the app and
    /// the widget can never drift onto two different completion code paths.
    /// Unavailable on watchOS, where `save` is prohibited — this is the function the
    /// *iPhone* calls on the Watch's behalf when a completion arrives over WatchConnectivity.
    #if !os(watchOS)
    @discardableResult
    public nonisolated static func completeReminder(externalID: String, in store: EKEventStore) throws -> Bool {
        guard let reminder = store.calendarItems(withExternalIdentifier: externalID)
            .compactMap({ $0 as? EKReminder }).first else { return false }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return true
    }
    #endif

    /// The pure `EKReminder` → `TaskItem` mapping, with no sidecar involved.
    ///
    /// Extracted so a widget extension — a separate, memory-constrained process with no
    /// reason to spin up the SwiftData sidecar for information it never displays (manual
    /// order, estimates) — can build the identical `TaskItem` shape the app itself uses,
    /// from a plain `EKEventStore` fetch, by passing a neutral rank and no estimate.
    public nonisolated static func makeTaskItem(
        from reminder: EKReminder, rank: Double, estimateMinutes: Int?,
        sectionID: String? = nil
    ) -> TaskItem? {
        guard let id = reminder.calendarItemExternalIdentifier,
              let calendar = reminder.calendar else { return nil }

        let due = reminder.dueDateComponents
        return TaskItem(
            id: id,
            title: reminder.title ?? "",
            notes: reminder.notes,
            url: reminder.url,
            listID: calendar.calendarIdentifier,
            listName: calendar.title,
            listColor: Self.rgba(from: calendar.cgColor),
            priority: Priority(reminderValue: Int(reminder.priority)),
            isCompleted: reminder.isCompleted,
            hasAlarms: !(reminder.alarms ?? []).isEmpty,
            isRecurring: reminder.hasRecurrenceRules,
            alarms: (reminder.alarms ?? []).map(alarmShape),
            recurrence: reminder.recurrenceRules?.first.map(recurrenceShape),
            plannedDay: Day(reminder.startDateComponents),
            dueDay: Day(due),
            dueIsTimed: Scheduling.isTimed(due),
            dueDate: due.flatMap { Day.gregorian.date(from: $0) },
            rank: rank,
            estimateMinutes: estimateMinutes,
            sectionID: sectionID
        )
    }

    /// Classifies an alarm so the UI knows whether it may be replaced.
    nonisolated static func alarmShape(_ alarm: EKAlarm) -> AlarmShape {
        if let location = alarm.structuredLocation, alarm.proximity != .none {
            return .location(
                title: location.title ?? "a location",
                isEntering: alarm.proximity == .enter
            )
        }
        if let absolute = alarm.absoluteDate { return .absolute(absolute) }
        return .relative(alarm.relativeOffset)
    }

    /// Classifies a repeat rule, recording whether it carries anything beyond
    /// frequency/interval/end — which is what makes it unsafe for this app to rewrite.
    nonisolated static func recurrenceShape(_ rule: EKRecurrenceRule) -> RecurrenceShape {
        let frequency: RecurrenceFrequency = switch rule.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        @unknown default: .daily
        }

        let end: RecurrenceEnd = if let recurrenceEnd = rule.recurrenceEnd {
            if let date = recurrenceEnd.endDate {
                .onDate(Day(date))
            } else {
                .afterCount(recurrenceEnd.occurrenceCount)
            }
        } else {
            .never
        }

        let positional = !(rule.daysOfTheWeek ?? []).isEmpty
            || !(rule.daysOfTheMonth ?? []).isEmpty
            || !(rule.monthsOfTheYear ?? []).isEmpty
            || !(rule.weeksOfTheYear ?? []).isEmpty
            || !(rule.daysOfTheYear ?? []).isEmpty
            || !(rule.setPositions ?? []).isEmpty

        return RecurrenceShape(
            frequency: frequency,
            interval: rule.interval,
            end: end,
            hasPositionalSpecifiers: positional
        )
    }

    nonisolated static func rgba(from cgColor: CGColor?) -> RGBA {
        guard let components = cgColor?.components, components.count >= 3 else { return .neutral }
        return RGBA(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            alpha: components.count > 3 ? Double(components[3]) : 1
        )
    }

#if !os(watchOS)
    // MARK: - Writing
    //
    // watchOS EventKit is read-only: `save`, `remove` and `commit` are all
    // `__WATCHOS_PROHIBITED`, so this entire surface is unavailable there. The Watch app
    // reads through `WidgetDataProvider` and proxies completions to the iPhone over
    // WatchConnectivity, which performs the write with `completeReminder` below.
    //
    // Guarded as one block deliberately. Sprinkling `#if` around individual `store.save`
    // calls would leave the surrounding functions compiling on watchOS while silently
    // doing nothing — a far worse failure than not existing at all.

    /// Adds a start date when iOS would otherwise refuse to save a due date.
    ///
    /// A no-op on macOS, which has no such requirement — guarding it keeps the Mac app's
    /// behaviour byte-for-byte unchanged rather than quietly giving every deadline a
    /// planned day.
    func satisfyStartDateRequirement(on reminder: EKReminder) {
        #if os(iOS)
        guard Scheduling.needsStartDateForDueDate(
            due: reminder.dueDateComponents, start: reminder.startDateComponents
        ) else { return }
        reminder.startDateComponents =
            Scheduling.startDateSatisfyingDueDate(reminder.dueDateComponents)
        #endif
    }

    /// Clears the planned day.
    ///
    /// Deliberately writes exactly what the user asked for and nothing more. `EKReminder`'s
    /// header states that iOS rejects a due date with no start date (`EKErrorNoStartDate`),
    /// which would make this fail on any task carrying a deadline — but measured against a
    /// live store on iOS 26 the save is accepted, start date and all, and the reminder
    /// comes back with `startDateComponents == nil`. See `saveRepairingStartDate`.
    ///
    /// Pre-emptively inventing a start date to satisfy a rule this platform does not
    /// enforce would store different data on iPhone than the Mac stores for the same
    /// gesture, which is the drift the shared core exists to prevent. So the repair is
    /// reactive: attempted only if a save genuinely comes back refused.
    func clearPlannedDay(on reminder: EKReminder) {
        reminder.startDateComponents = nil
    }

    /// Saves, repairing the one rejection the app can resolve on the user's behalf.
    ///
    /// The header documents `EKErrorNoStartDate` on iOS; the observed behaviour on iOS 26
    /// is that the save succeeds. Both are handled by trying the honest write first and
    /// only supplying a start date when the platform actually refuses without one — so a
    /// platform that enforces the rule still works, and one that doesn't is left alone.
    func saveRepairingStartDate(_ reminder: EKReminder, commit: Bool) throws {
        do {
            try store.save(reminder, commit: commit)
        } catch let error as NSError where Self.isMissingStartDate(error) {
            satisfyStartDateRequirement(on: reminder)
            try store.save(reminder, commit: commit)
        }
    }

    private static func isMissingStartDate(_ error: NSError) -> Bool {
        error.domain == EKErrorDomain && error.code == EKError.Code.noStartDate.rawValue
    }

    /// Resolves a live reminder for one of our value types.
    ///
    /// Looks up by external identifier rather than item identifier because the latter is
    /// documented as not sync-proof. The array form is used because a handful of edge
    /// cases (an event imported into several calendars, a shared calendar) can return
    /// duplicates; the reminder in the expected list wins.
    private func liveReminder(for task: TaskItem) -> EKReminder? {
        let matches = store.calendarItems(withExternalIdentifier: task.id)
            .compactMap { $0 as? EKReminder }
        return matches.first { $0.calendar?.calendarIdentifier == task.listID } ?? matches.first
    }

    /// Sets or clears a task's planned day. **Never touches the due date or alarms** —
    /// that invariant is what keeps a bill reminder firing exactly as before, and it is
    /// covered by the Phase 0 alarm-preservation test.
    public func schedule(_ task: TaskItem, to day: Day?) async {
        await performSchedule(task, to: day, recordUndo: true)
    }

    /// `recordUndo` is false when this *is* the undo, so undoing can't itself become the
    /// next undoable action and trap the user in a loop.
    private func performSchedule(_ task: TaskItem, to day: Day?, recordUndo: Bool) async {
        // Read the previous value off the *live* reminder, at the top of the closure and
        // before anything is written. See `mutate` for why the caller's snapshot will not do.
        var previous: Day?
        let saved = await mutate(task) { reminder in
            previous = Day(reminder.startDateComponents)
            if let day {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: day, alongside: reminder.dueDateComponents
                )
            } else {
                self.clearPlannedDay(on: reminder)
            }
        }
        if saved, recordUndo, previous != day {
            undoable = .reschedule(task: task, previousDay: previous)
        }
    }

    /// Drags the far end of a task's span to `day`.
    ///
    /// Dropping before the planned day extends the span *backwards* by moving the planned
    /// day instead, which is what the gesture visually implies. Otherwise the deadline
    /// moves. A task with no planned day gets one first, so a span always has two ends.
    public func setSpanEnd(_ task: TaskItem, to day: Day) async {
        await mutate(task) { reminder in
            let planned = Day(reminder.startDateComponents)

            if let planned, day < planned {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: day, alongside: reminder.dueDateComponents
                )
                return
            }

            // With no planned day, the task's existing deadline anchors the other end of
            // the span. The deadline may only ever move *later* here: dragging a handle
            // to say "start this Thursday" must never pull a real due date earlier.
            var deadlineDay = day
            if planned == nil {
                let anchor = Day(reminder.dueDateComponents) ?? .today()
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: min(anchor, day), alongside: reminder.dueDateComponents
                )
                deadlineDay = max(anchor, day)
            }
            reminder.dueDateComponents = Scheduling.deadlineComponents(
                for: deadlineDay, preserving: reminder.dueDateComponents
            )
            satisfyStartDateRequirement(on: reminder)
        }
    }

    /// Schedules many tasks in one transaction.
    ///
    /// The per-task path commits and refreshes each time, which for a whole overdue pile
    /// means one full EventKit fetch per item. Batching with `commit: false` collapses
    /// that into a single commit and a single refresh.
    public func schedule(_ batch: [TaskItem], to day: Day?) async {
        guard !batch.isEmpty else { return }
        var failed = 0
        // Captured before writing, so undo can put every task back on its own day rather
        // than on one shared day. This is the app's most far-reaching action; it needs a
        // way back at least as much as a single drag does.
        var previous: [PreviousSchedule] = []

        for task in batch {
            guard let reminder = liveReminder(for: task) else { failed += 1; continue }
            // From the live reminder, and only recorded once the save has been accepted —
            // an undo entry for a task that never moved would put it "back" to a day it is
            // already on, or to a day it has not been on for some time.
            let previousDay = Day(reminder.startDateComponents)
            if let day {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: day, alongside: reminder.dueDateComponents
                )
            } else {
                clearPlannedDay(on: reminder)
            }
            do {
                try saveRepairingStartDate(reminder, commit: false)
                previous.append(PreviousSchedule(task: task, previousDay: previousDay))
            } catch { failed += 1 }
        }

        var commitFailed = false
        do {
            markLocalWrite()
            try store.commit()
        } catch {
            commitFailed = true
            // A failed commit means nothing was written at all, which is a different and
            // more important story than "some tasks could not be resolved" — so it wins
            // rather than being overwritten by the count below.
            lastError = "Could not reschedule: \(error.localizedDescription)"
        }
        if !commitFailed, failed > 0 {
            lastError = "\(failed) task\(failed == 1 ? "" : "s") could not be rescheduled."
        }
        if !commitFailed, !previous.isEmpty {
            undoable = .bulkReschedule(items: previous)
        }
        await refresh()
    }

    /// Clears the deadline end of a span, leaving the task planned for a single day.
    public func clearSpanEnd(_ task: TaskItem) async {
        var previous: Day?
        let saved = await mutate(task) { reminder in
            previous = Day(reminder.dueDateComponents)
            reminder.dueDateComponents = nil
        }
        if saved, previous != nil {
            undoable = .deadline(task: task, previousDue: previous)
        }
    }

    /// The last reversible edit, or nil when there is nothing to undo.
    ///
    /// Completed reminders vanish from `tasks` — the only fetch is
    /// `predicateForIncompleteReminders` — so without holding the value here there is no
    /// way back from a mis-click except opening Reminders.app. Lookup still works because
    /// `calendarItems(withExternalIdentifier:)` is a direct lookup, not a predicate.
    public private(set) var undoable: UndoableAction?

    public func setCompleted(_ task: TaskItem, _ completed: Bool) async {
        guard await mutate(task, { $0.isCompleted = completed }) else { return }
        // Un-completing is itself the undo of completing; recording it would let someone
        // toggle a task forever via the undo banner.
        undoable = completed ? .complete(task: task) : nil
    }

    /// Reverses the last edit and clears the slot. Safe to call when empty.
    public func undoLast() async {
        guard let action = undoable else { return }
        undoable = nil
        switch action {
        case let .reschedule(task, previousDay):
            await performSchedule(task, to: previousDay, recordUndo: false)
        case let .deadline(task, previousDue):
            await performSetDueDay(task, to: previousDue, recordUndo: false)
        case let .move(task, previousListID, _):
            await performMove(task, toList: previousListID, recordUndo: false)
        case let .complete(task):
            await mutate(task) { $0.isCompleted = false }
        case let .bulkReschedule(items):
            await restore(items)
        }
    }

    /// Puts a batch of tasks back on their individual previous days, in one commit.
    private func restore(_ items: [PreviousSchedule]) async {
        for item in items {
            guard let reminder = liveReminder(for: item.task) else { continue }
            if let day = item.previousDay {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: day, alongside: reminder.dueDateComponents
                )
            } else {
                clearPlannedDay(on: reminder)
            }
            try? saveRepairingStartDate(reminder, commit: false)
        }
        markLocalWrite()
        do { try store.commit() } catch {
            lastError = "Could not undo: \(error.localizedDescription)"
        }
        await refresh()
    }

    public func dismissUndo() { undoable = nil }

    /// Replaces the repeat rule, or clears it when `rule` is nil.
    ///
    /// Refuses outright when the existing rule carries specifiers this app cannot express
    /// (days of the week, set positions and so on). The UI does not offer the control in
    /// that case, but the guard lives here too so no future caller can quietly discard
    /// part of a rule the user built in Reminders.
    @discardableResult
    public func setRecurrence(_ task: TaskItem, _ rule: SimpleRecurrence?) async -> Bool {
        await mutate(task) { reminder in
            // Both guards read the live reminder rather than `task`: a snapshot taken when
            // the detail view opened may predate a rule or deadline changed elsewhere, and
            // deciding from it either clobbers a rule this app cannot rebuild or refuses an
            // edit that is perfectly valid.
            if let existing = reminder.recurrenceRules?.first.map(Self.recurrenceShape),
               !existing.isEditableHere {
                throw Refusal(message: "That repeat rule is more detailed than this app can edit. Change it in Reminders.")
            }
            // A repeat rule is anchored to the deadline. Verified against live EventKit:
            // adding one to a reminder with no due date is accepted in memory and silently
            // dropped on save, so refusing loudly beats appearing to work.
            if rule != nil, reminder.dueDateComponents == nil {
                throw Refusal(message: "Set a deadline before making “\(task.title)” repeat — a repeat needs a date to repeat from.")
            }

            for existing in reminder.recurrenceRules ?? [] {
                reminder.removeRecurrenceRule(existing)
            }
            guard let rule else { return }

            let frequency: EKRecurrenceFrequency = switch rule.frequency {
            case .daily: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            }
            let end: EKRecurrenceEnd? = switch rule.end {
            case .never: nil
            case let .onDate(day): EKRecurrenceEnd(end: day.startOfDay())
            case let .afterCount(n): EKRecurrenceEnd(occurrenceCount: max(1, n))
            }
            reminder.addRecurrenceRule(
                EKRecurrenceRule(recurrenceWith: frequency, interval: rule.interval, end: end)
            )
        }
    }

    /// Sets a single absolute alarm, or clears all alarms when `date` is nil.
    ///
    /// Refuses when any existing alarm is a geofence: this app has no way to rebuild one,
    /// so replacing it would silently turn "remind me when I get to the studio" into a
    /// fixed time, or into nothing at all.
    @discardableResult
    public func setAlarm(_ task: TaskItem, at date: Date?) async -> Bool {
        await mutate(task) { reminder in
            // Read the live alarms, not `task.alarms`. A geofence added in Reminders while
            // this detail view was open is absent from the snapshot, and clearing alarms
            // from a stale check would delete it with no way to rebuild it.
            let live = (reminder.alarms ?? []).map(Self.alarmShape)
            if live.contains(where: { !$0.isEditableHere }) {
                throw Refusal(message: "That reminder has a location alert this app can't edit. Change it in Reminders.")
            }
            for existing in reminder.alarms ?? [] {
                reminder.removeAlarm(existing)
            }
            if let date {
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }
    }

    public func setPriority(_ task: TaskItem, _ priority: Priority) async {
        await mutate(task) { $0.priority = priority.rawValue }
    }

    public func setTitle(_ task: TaskItem, _ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }   // Reminders has no concept of a blank task
        await mutate(task) { $0.title = trimmed }
    }

    /// Empty notes are written back as nil so Reminders does not keep an empty body.
    public func setNotes(_ task: TaskItem, _ notes: String) async {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        await mutate(task) { $0.notes = trimmed.isEmpty ? nil : trimmed }
    }

    public func setURL(_ task: TaskItem, _ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        await mutate(task) { $0.url = trimmed.isEmpty ? nil : URL(string: trimmed) }
    }

    /// Writes the free-text fields together, in one commit.
    ///
    /// The detail panel and the phone's task sheet both collect title, notes and URL while
    /// you type and commit on dismiss. Sending them as three separate edits meant three
    /// EventKit commits and three full refetches for a single "Done" — and, because each
    /// was its own detached `Task`, in no guaranteed order. Pass nil for a field that has
    /// not changed.
    public func setFields(
        _ task: TaskItem, title: String? = nil, notes: String? = nil, url: String? = nil
    ) async {
        guard title != nil || notes != nil || url != nil else { return }
        await mutate(task) { reminder in
            if let title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                // Reminders has no concept of a blank task, so an emptied title is ignored
                // rather than written — matching `setTitle`.
                if !trimmed.isEmpty { reminder.title = trimmed }
            }
            if let notes {
                let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                reminder.notes = trimmed.isEmpty ? nil : trimmed
            }
            if let url {
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                reminder.url = trimmed.isEmpty ? nil : URL(string: trimmed)
            }
        }
    }

    /// Sets or clears the wall-clock time on the deadline, keeping the day it already has.
    ///
    /// Writing a time is what makes a reminder non-all-day, which is the distinction the
    /// original spike turned up: `allDay` belongs to the item rather than to each date, so
    /// a timed deadline needs a timed start alongside it or the time is silently stripped.
    /// `satisfyStartDateRequirement` and `Scheduling.plannedComponents` between them keep
    /// that invariant.
    public func setDueTime(_ task: TaskItem, hour: Int?, minute: Int?) async {
        await mutate(task) { reminder in
            guard let due = Scheduling.settingTime(
                on: reminder.dueDateComponents, hour: hour, minute: minute
            ) else { return }
            reminder.dueDateComponents = due

            // The planned day must follow the deadline's timed-ness or the all-day
            // coercion strips the time straight back off.
            if let plannedDay = Day(reminder.startDateComponents) {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: plannedDay, alongside: due
                )
            }
            satisfyStartDateRequirement(on: reminder)
        }
    }

    /// Sets or clears the deadline directly, preserving any time of day already on it.
    ///
    /// Distinct from `setSpanEnd`, which is the drag gesture and refuses to move a
    /// deadline earlier. Here the user is editing the date outright, so both directions
    /// are theirs to choose.
    public func setDueDay(_ task: TaskItem, to day: Day?) async {
        await performSetDueDay(task, to: day, recordUndo: true)
    }

    private func performSetDueDay(_ task: TaskItem, to day: Day?, recordUndo: Bool) async {
        var previous: Day?
        let saved = await mutate(task) { reminder in
            previous = Day(reminder.dueDateComponents)
            guard let day else {
                reminder.dueDateComponents = nil
                return
            }
            reminder.dueDateComponents = Scheduling.deadlineComponents(
                for: day, preserving: reminder.dueDateComponents
            )
            // iOS may refuse a due date with no start date; see Scheduling.
            satisfyStartDateRequirement(on: reminder)
        }
        if saved, recordUndo, previous != day {
            undoable = .deadline(task: task, previousDue: previous)
        }
    }

    public func move(_ task: TaskItem, toList listID: String) async {
        await performMove(task, toList: listID, recordUndo: true)
    }

    private func performMove(_ task: TaskItem, toList listID: String, recordUndo: Bool) async {
        guard let calendar = store.calendar(withIdentifier: listID) else { return }
        var previousID: String?
        var previousName: String?
        let saved = await mutate(task) { reminder in
            previousID = reminder.calendar?.calendarIdentifier
            // Falls back to the snapshot's name only for the label. The *identifier* is what
            // undo acts on and is never taken from the snapshot.
            previousName = reminder.calendar?.title ?? task.listName
            reminder.calendar = calendar
        }
        if saved, recordUndo, let previousID, previousID != listID {
            undoable = .move(
                task: task, previousListID: previousID, previousListName: previousName ?? task.listName
            )
        }
    }

    public func delete(_ task: TaskItem) async {
        guard let reminder = liveReminder(for: task) else { return }
        do {
            markLocalWrite()
            try store.remove(reminder, commit: true)
            // A pending undo that points at this task can no longer be carried out, and
            // offering it would only produce "no longer in Reminders" when tapped.
            if undoable?.involves(task.id) == true { undoable = nil }
            await refresh()
        } catch {
            lastError = "Could not delete “\(task.title)”: \(error.localizedDescription)"
        }
    }

    /// Creates a reminder and returns its `calendarItemExternalIdentifier`, so a caller
    /// that needs to attach sidecar state to it — a section, say — can do so without
    /// having to guess which of the refreshed tasks is the new one by title.
    @discardableResult
    public func create(
        title: String,
        in listID: String,
        on day: Day?,
        notes: String? = nil,
        due: Day? = nil,
        priority: Priority = .none
    ) async -> String? {
        guard let calendar = store.calendar(withIdentifier: listID) else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        reminder.priority = priority.rawValue
        if let notes, !notes.isEmpty { reminder.notes = notes }
        if let due {
            reminder.dueDateComponents = Scheduling.deadlineComponents(for: due, preserving: nil)
        }
        if let day {
            reminder.startDateComponents = Scheduling.plannedComponents(
                for: day, alongside: reminder.dueDateComponents
            )
        }
        satisfyStartDateRequirement(on: reminder)
        do {
            markLocalWrite()
            try store.save(reminder, commit: true)
            // Read after the save: the external identifier is assigned by the store, and
            // is nil on a reminder that has never been committed.
            let id = reminder.calendarItemExternalIdentifier
            await refresh()
            return id
        } catch {
            lastError = "Could not create “\(title)”: \(error.localizedDescription)"
            return nil
        }
    }

    /// Thrown by a `mutate` closure that has looked at the live reminder and decided the
    /// edit must not go ahead. Carries the message the user sees; nothing is saved.
    struct Refusal: Error { let message: String }

    /// Applies an edit to the live `EKReminder`, letting the closure veto after it has
    /// seen the real object.
    ///
    /// The veto exists because a `TaskItem` is a snapshot taken whenever the caller last
    /// refetched, and every detail view holds one for as long as it is open. A guard that
    /// reads the snapshot is validating what the reminder looked like some time ago, not
    /// what this write is about to overwrite — so a geofence alarm added on another device
    /// in the meantime would be invisible to the check and destroyed by the write. Guards
    /// therefore run *here*, against the same object the save touches.
    ///
    /// The same staleness applies to **undo**. An entry records the value a field held
    /// before the edit, and taking that from `task` records what the field held whenever
    /// the caller last refetched — so two edits to one field from a single open detail
    /// panel both record the original value, and the intermediate one is unreachable. Every
    /// `previous` in this file is therefore read off `reminder` at the top of the closure.
    ///
    /// Contract, in both directions: **a closure reads before it writes.** Reads that happen
    /// after a mutation see the new value, and a throw after a mutation leaves it stranded
    /// on the shared instance until the next refetch, since `EKReminder` is a live reference.
    ///
    /// Returns whether the write actually landed. Callers recording undo must honour it —
    /// offering to reverse an edit that was refused or failed is offering to overwrite the
    /// current value with a stale one.
    ///
    /// Taking a `throws` closure rather than overloading keeps the majority of edits — the
    /// ones with no precondition to check — written exactly as they were.
    @discardableResult
    private func mutate(_ task: TaskItem, _ body: (EKReminder) throws -> Void) async -> Bool {
        guard let reminder = liveReminder(for: task) else {
            lastError = "“\(task.title)” is no longer in Reminders."
            return false
        }
        do {
            try body(reminder)
        } catch let refusal as Refusal {
            lastError = refusal.message
            return false
        } catch {
            lastError = "Could not edit “\(task.title)”: \(error.localizedDescription)"
            return false
        }
        do {
            markLocalWrite()
            try saveRepairingStartDate(reminder, commit: true)
            await refresh()
            return true
        } catch {
            lastError = "Could not save “\(task.title)”: \(error.localizedDescription)"
            return false
        }
    }

#endif

    // MARK: - Ordering (sidecar only, never round-trips to Reminders)

    /// Places `task` between two neighbours. Sidecar only — Reminders has no ordering
    /// field, so this never round-trips.
    ///
    /// `neighbourhood` is the column the drop happened in. It matters because board
    /// columns are grouped by *day*, not by list, so a respread has to renumber the set
    /// the user is actually looking at.
    public func reorder(
        _ task: TaskItem,
        above: TaskItem?,
        below: TaskItem?,
        within neighbourhood: [TaskItem]? = nil
    ) {
        guard let meta else { return }
        if let rank = Ranking.between(above?.rank, below?.rank) {
            meta.setRank(rank, for: task.id)
            applyLocalRanks()
            return
        }

        // Gap exhausted after many drops into the same slot: respread, then recompute the
        // target from the *new* neighbour ranks. Reusing the pre-respread values would
        // drop the card at an arbitrary position.
        let column = (neighbourhood ?? tasks.filter { $0.listID == task.listID })
            .sorted { $0.rank < $1.rank }
        let respread = Ranking.respread(column.map(\.id), above: above?.id, below: below?.id)
        var ranks = respread.ranks
        // Recomputed from the *new* neighbour values. Reusing the pre-respread ones would
        // drop the card at an arbitrary position — see `Ranking.respread`.
        if let rank = Ranking.between(respread.above, respread.below) {
            ranks[task.id] = rank
        }
        meta.setRanks(ranks)
        applyLocalRanks()
    }

    public func setEstimate(_ minutes: Int?, for task: TaskItem) {
        guard let meta else { return }
        meta.setEstimate(minutes, for: task.id)
        applyLocalRanks()
    }

    /// Files a task into one of its list's sections, or out of all of them.
    ///
    /// Sidecar-only, so this never touches Reminders and never triggers a refetch — which
    /// is what lets a drag between columns land instantly.
    public func setSection(_ sectionID: String?, for task: TaskItem) {
        guard let meta else { return }
        meta.setSection(sectionID, for: task.id)
        applyLocalRanks()
    }

    /// Files many tasks at once — deleting a section empties it in one transaction rather
    /// than one save per task.
    public func setSections(_ assignments: [String: String?]) {
        guard let meta else { return }
        meta.setSections(assignments)
        applyLocalRanks()
    }

    /// Re-reads every sidecar value into the published tasks.
    ///
    /// For changes made to the sidecar from outside this type — deleting a section re-files
    /// everything that was in it, and the board has to see that without a round trip to
    /// Reminders, which knows nothing about sections in the first place.
    public func reloadSidecar() { applyLocalRanks() }

    /// Re-reads sidecar values into the published tasks without a Reminders round trip,
    /// so a drag-to-reorder feels instant.
    private func applyLocalRanks() {
        guard let meta else { return }
        // One indexed read for the whole list. This used to be a predicate fetch per task,
        // on the path whose entire purpose is to make a drag feel instant.
        let index = meta.indexedByExternalID()
        tasks = tasks.map { task in
            guard let row = index[task.id] else { return task }
            var copy = task
            copy.rank = row.rank
            copy.estimateMinutes = row.estimateMinutes
            copy.sectionID = row.sectionID
            return copy
        }
        dataRevision &+= 1
    }

    public func clearError() { lastError = nil }
}

// MARK: - Calendar overlay
//
// Events are read-only and entirely optional: the overlay answers "is Thursday already
// spoken for?" and nothing more. Calendar access is a *separate* TCC permission from
// reminders, and it is requested lazily — only when the overlay is first switched on —
// so declining it costs nothing and the app keeps working in full.

extension ReminderStore {

    public static func eventAccessState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        // Write-only is genuinely useless here: the overlay only ever reads.
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .unknown
        }
    }

    public func requestEventAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            eventAccess = granted ? .granted : .denied
            if granted { refreshCalendars() }
        } catch {
            lastError = "Could not request Calendar access: \(error.localizedDescription)"
            eventAccess = .denied
        }
    }

    public func refreshCalendars() {
        guard eventAccess == .granted else { return }
        calendars = store.calendars(for: .event).map {
            EventCalendar(
                id: $0.calendarIdentifier,
                title: $0.title,
                color: Self.rgba(from: $0.cgColor)
            )
        }
    }

    /// Loads the overlay for a date range. Called whenever the visible week or the
    /// selected calendars change; passing an empty selection clears the overlay without
    /// touching EventKit at all.
    public func refreshEvents(from start: Date, to end: Date, calendarIDs: Set<String>) {
        guard eventAccess == .granted, !calendarIDs.isEmpty else {
            events = []
            return
        }
        let selected = store.calendars(for: .event)
            .filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        events = store.events(matching: predicate).map { event in
            CalendarEvent(
                // Recurring occurrences share an identifier, so the start date
                // disambiguates them.
                id: "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "(No title)",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarID: event.calendar?.calendarIdentifier ?? "",
                calendarName: event.calendar?.title ?? "",
                color: Self.rgba(from: event.calendar?.cgColor),
                location: event.location?.isEmpty == false ? event.location : nil
            )
        }
        .sorted { lhs, rhs in
            // All-day events read as the header of a day, so they sort above timed ones.
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.start < rhs.start
        }
    }
}
