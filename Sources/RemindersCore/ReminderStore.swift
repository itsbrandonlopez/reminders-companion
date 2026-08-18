import EventKit
import Foundation
import Observation

#if canImport(AppKit)
import AppKit
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
    private let meta: MetaStore
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

    public init(meta: MetaStore) {
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

    #if canImport(AppKit)
    public func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        NSWorkspace.shared.open(url)
    }
    #endif

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
                // Skip the echo of a change this app just made.
                guard Date.now.timeIntervalSince(self.lastLocalWrite) > Self.localWriteEcho
                else { return }
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
    }

    // MARK: - Reading

    public func refresh() async {
        guard access == .granted else { return }
        isLoading = true
        defer { isLoading = false }

        lists = store.calendars(for: .reminder).map { calendar in
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

        var living = Set<String>()
        var items: [TaskItem] = []
        items.reserveCapacity(reminders.count)

        for (index, reminder) in reminders.enumerated() {
            // Seeded so an untouched column reads high-priority-first, while any manual
            // reordering afterwards wins outright.
            let seed = Double(Priority(reminderValue: Int(reminder.priority)).sortWeight) * 1_000_000
                + Double(index) * Ranking.step
            guard let item = makeItem(reminder, fallbackRank: seed) else { continue }
            living.insert(item.id)
            items.append(item)
        }

        meta.save()
        // `living` holds only *incomplete* reminders, so it is not a list of what still
        // exists — completing a task would otherwise delete its estimate and manual
        // position. Collection is by staleness instead.
        meta.collectGarbage(livingIDs: living)
        tasks = items
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

    private func makeItem(_ reminder: EKReminder, fallbackRank: Double) -> TaskItem? {
        guard let id = reminder.calendarItemExternalIdentifier,
              let calendar = reminder.calendar else { return nil }

        let row = meta.ensure(id, title: reminder.title ?? "", defaultRank: fallbackRank)
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
            plannedDay: Day(reminder.startDateComponents),
            dueDay: Day(due),
            dueIsTimed: Scheduling.isTimed(due),
            dueDate: due.flatMap { Day.gregorian.date(from: $0) },
            rank: row.rank,
            estimateMinutes: row.estimateMinutes
        )
    }

    static func rgba(from cgColor: CGColor?) -> RGBA {
        guard let components = cgColor?.components, components.count >= 3 else { return .neutral }
        return RGBA(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            alpha: components.count > 3 ? Double(components[3]) : 1
        )
    }

    // MARK: - Writing

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
        await mutate(task) { reminder in
            if let day {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: day, alongside: reminder.dueDateComponents
                )
            } else {
                reminder.startDateComponents = nil
            }
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
        for task in batch {
            guard let reminder = liveReminder(for: task) else { failed += 1; continue }
            if let day {
                reminder.startDateComponents = Scheduling.plannedComponents(
                    for: day, alongside: reminder.dueDateComponents
                )
            } else {
                reminder.startDateComponents = nil
            }
            do { try store.save(reminder, commit: false) } catch { failed += 1 }
        }
        do {
            markLocalWrite()
            try store.commit()
        } catch {
            lastError = "Could not reschedule: \(error.localizedDescription)"
        }
        if failed > 0 {
            lastError = "\(failed) task\(failed == 1 ? "" : "s") could not be rescheduled."
        }
        await refresh()
    }

    /// Clears the deadline end of a span, leaving the task planned for a single day.
    public func clearSpanEnd(_ task: TaskItem) async {
        await mutate(task) { $0.dueDateComponents = nil }
    }

    /// The task most recently ticked off, retained so it can be un-ticked.
    ///
    /// Completed reminders vanish from `tasks` — the only fetch is
    /// `predicateForIncompleteReminders` — so without holding onto this value there is no
    /// way back from a mis-click except opening Reminders.app. Lookup still works because
    /// `calendarItems(withExternalIdentifier:)` is a direct lookup, not a predicate.
    public private(set) var undoableCompletion: TaskItem?

    public func setCompleted(_ task: TaskItem, _ completed: Bool) async {
        await mutate(task) { $0.isCompleted = completed }
        undoableCompletion = completed ? task : nil
    }

    public func undoLastCompletion() async {
        guard let task = undoableCompletion else { return }
        undoableCompletion = nil
        await mutate(task) { $0.isCompleted = false }
    }

    public func dismissUndo() { undoableCompletion = nil }

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

    /// Sets or clears the deadline directly, preserving any time of day already on it.
    ///
    /// Distinct from `setSpanEnd`, which is the drag gesture and refuses to move a
    /// deadline earlier. Here the user is editing the date outright, so both directions
    /// are theirs to choose.
    public func setDueDay(_ task: TaskItem, to day: Day?) async {
        await mutate(task) { reminder in
            guard let day else {
                reminder.dueDateComponents = nil
                return
            }
            reminder.dueDateComponents = Scheduling.deadlineComponents(
                for: day, preserving: reminder.dueDateComponents
            )
        }
    }

    public func move(_ task: TaskItem, toList listID: String) async {
        guard let calendar = store.calendar(withIdentifier: listID) else { return }
        await mutate(task) { $0.calendar = calendar }
    }

    public func delete(_ task: TaskItem) async {
        guard let reminder = liveReminder(for: task) else { return }
        do {
            markLocalWrite()
            try store.remove(reminder, commit: true)
            await refresh()
        } catch {
            lastError = "Could not delete “\(task.title)”: \(error.localizedDescription)"
        }
    }

    public func create(
        title: String,
        in listID: String,
        on day: Day?,
        notes: String? = nil,
        due: Day? = nil,
        priority: Priority = .none
    ) async {
        guard let calendar = store.calendar(withIdentifier: listID) else { return }
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
        do {
            markLocalWrite()
            try store.save(reminder, commit: true)
            await refresh()
        } catch {
            lastError = "Could not create “\(title)”: \(error.localizedDescription)"
        }
    }

    private func mutate(_ task: TaskItem, _ body: (EKReminder) -> Void) async {
        guard let reminder = liveReminder(for: task) else {
            lastError = "“\(task.title)” is no longer in Reminders."
            return
        }
        body(reminder)
        do {
            markLocalWrite()
            try store.save(reminder, commit: true)
            await refresh()
        } catch {
            lastError = "Could not save “\(task.title)”: \(error.localizedDescription)"
        }
    }

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
        for (rank, item) in zip(Ranking.normalized(count: column.count), column) {
            meta.setRank(rank, for: item.id)
        }
        let freshAbove = above.flatMap { meta.meta(for: $0.id)?.rank }
        let freshBelow = below.flatMap { meta.meta(for: $0.id)?.rank }
        if let rank = Ranking.between(freshAbove, freshBelow) {
            meta.setRank(rank, for: task.id)
        }
        applyLocalRanks()
    }

    public func setEstimate(_ minutes: Int?, for task: TaskItem) {
        meta.setEstimate(minutes, for: task.id)
        applyLocalRanks()
    }

    /// Re-reads sidecar values into the published tasks without a Reminders round trip,
    /// so a drag-to-reorder feels instant.
    private func applyLocalRanks() {
        tasks = tasks.map { task in
            guard let row = meta.meta(for: task.id) else { return task }
            var copy = task
            copy.rank = row.rank
            copy.estimateMinutes = row.estimateMinutes
            return copy
        }
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
