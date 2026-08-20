import Observation
import RemindersCore
import SwiftUI

/// The phone's object graph.
///
/// Thinner than the Mac's `AppEnvironment`, but no longer sidecar-free. It used to be:
/// manual order, estimates, folders and sections lived in a **local** database on one Mac,
/// so carrying one here meant reconciling a SwiftData row per reminder on every refresh to
/// store values nothing on this platform could ever read.
///
/// Putting that database on CloudKit is what changed the arithmetic. The rows now arrive
/// with content — the order you dragged things into on the Mac, the sections you named —
/// so reconciling them buys something. Everything else still comes through Reminders
/// itself, which needs no sync layer because it was never a copy.
@MainActor
@Observable
final class MobileEnvironment {
    let store: ReminderStore

    /// The sidecar, when one could be opened. Nil is survivable and always has been: the
    /// store seeds ranks from priority without it, which is what this app sorted by
    /// before there was one.
    let meta: MetaStore?

    /// Whether the sidecar is reaching iCloud, for the settings row that says so. An
    /// unsigned or unentitled build gets `.local`, where sections typed on the Mac will
    /// never appear here and the app should say that rather than look broken.
    var sidecarStorage: MetaStore.Storage { meta?.storage ?? .local }

    var selectedListIDs: Set<String> = [] {
        didSet { defaults.set(Array(selectedListIDs), forKey: Self.listsKey) }
    }

    private(set) var hasCompletedSetup = false
    var overlayCalendarIDs: Set<String> = [] {
        didSet {
            defaults.set(Array(overlayCalendarIDs), forKey: Self.overlayKey)
            reloadOverlay()
        }
    }

    var weekAnchor: Day = .today()

    /// Set by a tapped widget's deep link. `RootTabView` observes this to switch tabs;
    /// `TodayView` observes it to present that task's detail sheet once found. Cleared by
    /// whichever view consumes it, so a stale link never re-fires.
    var requestedTab: Int?
    var pendingTaskID: String?

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "reminderscompanion" else { return }
        requestedTab = 0   // Today
        if url.host == "task" {
            let id = url.pathComponents.dropFirst().first
            pendingTaskID = id
        }
    }

    private let defaults = UserDefaults.standard
    private static let listsKey = "mobile.selectedListIDs"
    private static let overlayKey = "mobile.overlayCalendarIDs"
    private static let setupKey = "mobile.hasCompletedSetup"

    init() {
        // Failing to open the sidecar is never fatal here. It carries arrangement — order,
        // estimates, sections — and losing it costs exactly that, while every task, list
        // and date still arrives through Reminders untouched.
        let meta = try? MetaStore()
        self.meta = meta
        store = ReminderStore(meta: meta)
        selectedListIDs = Set(defaults.stringArray(forKey: Self.listsKey) ?? [])
        overlayCalendarIDs = Set(defaults.stringArray(forKey: Self.overlayKey) ?? [])
        hasCompletedSetup = defaults.bool(forKey: Self.setupKey)
    }

    func completeSetup() {
        hasCompletedSetup = true
        defaults.set(true, forKey: Self.setupKey)
    }

    func restartSetup() {
        hasCompletedSetup = false
        defaults.set(false, forKey: Self.setupKey)
    }

    // MARK: - Slices

    private var activeListIDs: Set<String> {
        selectedListIDs.isEmpty ? Set(store.lists.map(\.id)) : selectedListIDs
    }

    var week: [Day] { Scheduling.week(containing: weekAnchor) }

    // MARK: - Derived slices
    //
    // Computed once behind a key, for the same reason as the Mac's — more acutely, in fact.
    // `tasks(on:)` used to re-derive `triaged`, which re-derived `backlog` *and*
    // `unscheduled`, each of which re-derived and re-sorted `tasks`: three full sorts per
    // call, and `WeekView` calls it ten times per render between the day strip and the
    // blocks.

    private struct SliceKey: Equatable {
        let dataRevision: Int
        let selectedListIDs: Set<String>
        let listCount: Int
        let today: Day
        /// Constant for the life of the process, but carried here so the two sort orders
        /// can never be served from a cache built under the other one.
        let honoursManualOrder: Bool
    }

    private struct Slices {
        var tasks: [TaskItem] = []
        var backlog: [TaskItem] = []
        var unscheduled: [TaskItem] = []
        var byDay: [Day: [TaskItem]] = [:]
    }

    // Not observed: a memo of observable state, written from the getters that read it.
    @ObservationIgnored private var cacheKey: SliceKey?
    @ObservationIgnored private var cache = Slices()

    private var slices: Slices {
        let key = SliceKey(
            dataRevision: store.dataRevision,
            selectedListIDs: selectedListIDs,
            listCount: store.lists.count,
            today: .today(),
            honoursManualOrder: meta != nil
        )
        if key == cacheKey { return cache }
        let built = buildSlices(key)
        cacheKey = key
        cache = built
        return built
    }

    private func buildSlices(_ key: SliceKey) -> Slices {
        var out = Slices()
        let active = activeListIDs
        let weekStart = Scheduling.week(containing: key.today).first ?? key.today

        let visible = store.tasks.filter { active.contains($0.listID) && !$0.isCompleted }

        if key.honoursManualOrder {
            // The order you dragged things into on the Mac, arriving through iCloud. Rank
            // alone: it is seeded from priority for anything never touched, so an
            // unorganised list still reads high-priority-first.
            out.tasks = visible.sorted { $0.rank < $1.rank }
        } else {
            // No sidecar. Priority then day, which is what this app did before there was
            // any ordering to honour.
            out.tasks = visible.sorted { lhs, rhs in
                if lhs.priority.sortWeight != rhs.priority.sortWeight {
                    return lhs.priority.sortWeight < rhs.priority.sortWeight
                }
                return (lhs.boardDay ?? key.today) < (rhs.boardDay ?? key.today)
            }
        }

        for task in out.tasks {
            switch Scheduling.bucket(
                plannedDay: task.plannedDay, dueDay: task.dueDay, currentWeekStart: weekStart
            ) {
            case .backlog:
                out.backlog.append(task)
            case .unscheduled:
                out.unscheduled.append(task)
            case let .day(day):
                // The two triage piles are held back, so the day and week views stay clean.
                out.byDay[day, default: []].append(task)
            }
        }
        out.backlog.sort { ($0.boardDay ?? key.today) < ($1.boardDay ?? key.today) }
        return out
    }

    /// The Mac's manual order when a sidecar is reaching this device, priority then day
    /// when it is not.
    var tasks: [TaskItem] { slices.tasks }

    /// Work that slipped past the whole of the current week. Same rule as the Mac.
    var backlog: [TaskItem] { slices.backlog }

    var unscheduled: [TaskItem] { slices.unscheduled }

    /// Only dated work, with the two triage piles held back.
    func tasks(on day: Day) -> [TaskItem] { slices.byDay[day] ?? [] }

    var todaysTasks: [TaskItem] { tasks(on: .today()) }

    /// How many tasks are in the Triage backlog — work that slipped past the *whole*
    /// current week, matching the Mac's Backlog column.
    ///
    /// Named for the pile it counts rather than "past due", which reads as "deadline has
    /// passed" and is a different, larger set (`TaskItem.isOverdue`). The banner on Today
    /// links straight to this pile, so it has to count exactly what the pile holds.
    var backlogCount: Int { backlog.count }

    // MARK: - Sections

    /// One list's sections, in the order they are arranged on the Mac. Empty when the list
    /// has none, or when there is no sidecar reaching this device.
    func sections(in listID: String) -> [ListSection] {
        meta?.sections(in: listID) ?? []
    }

    /// Every task in one list, ignoring the list filter — a list you opened deliberately
    /// is not a list you meant to hide.
    func tasks(in listID: String) -> [TaskItem] {
        let ordered = store.tasks.filter { $0.listID == listID && !$0.isCompleted }
        return meta != nil
            ? ordered.sorted { $0.rank < $1.rank }
            : ordered.sorted { $0.priority.sortWeight < $1.priority.sortWeight }
    }

    // MARK: - Quick add

    /// Creates a task from raw quick-add text, honouring any `!` priority, `#list` and
    /// natural-language date it contains. Shares `QuickAddParser` with the Mac app, so
    /// the shorthand behaves identically on both.
    ///
    /// `defaultDay` is what the surrounding view implies — Today passes today, Triage's
    /// no-date pile passes nil. An explicit date in the text overrides it.
    func quickAdd(_ input: String, defaultDay: Day?) async {
        let parsed = QuickAddParser.parse(input)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let editable = store.lists.filter(\.isEditable)
        let listID = parsed.listToken
            .flatMap { QuickAddParser.matchList($0, in: editable)?.id }
            ?? editable.first(where: \.isDefault)?.id
            ?? editable.first?.id
        guard let listID else { return }

        await store.create(
            title: title,
            in: listID,
            on: parsed.day ?? defaultDay,
            priority: parsed.priority ?? .none
        )
    }

    // MARK: - Calendar overlay

    func events(on day: Day) -> [CalendarEvent] {
        store.events.filter { $0.occupies(day) }
    }

    func bookedMinutes(on day: Day) -> Int {
        events(on: day).filter { !$0.isAllDay }.reduce(0) { $0 + $1.durationMinutes }
    }

    /// A single line per day rather than event cards — enough to answer "am I free?"
    /// without turning the week into a calendar app.
    func overlaySummary(on day: Day) -> String? {
        let all = events(on: day)
        guard !all.isEmpty else { return nil }
        let minutes = bookedMinutes(on: day)
        let hours = minutes >= 60 ? String(format: "%.1fh", Double(minutes) / 60) : "\(minutes)m"
        if all.count == 1 { return minutes > 0 ? "\(all[0].title) · \(hours)" : all[0].title }
        return minutes > 0 ? "\(all.count) events · \(hours)" : "\(all.count) events"
    }

    func enableOverlay() async {
        if store.eventAccess == .notDetermined { await store.requestEventAccess() }
        guard store.eventAccess == .granted else { return }
        store.refreshCalendars()
        reloadOverlay()
    }

    func loadOverlayIfAuthorized() {
        guard store.eventAccess == .granted else { return }
        store.refreshCalendars()
        reloadOverlay()
    }

    func reloadOverlay() {
        guard let first = week.first, let last = week.last else { return }
        store.refreshEvents(
            from: first.adding(days: -1).startOfDay(),
            to: last.adding(days: 2).startOfDay(),
            calendarIDs: overlayCalendarIDs
        )
    }

    func jumpWeek(_ delta: Int) {
        weekAnchor = weekAnchor.adding(days: delta * 7)
        reloadOverlay()
    }

    func goToToday() {
        weekAnchor = .today()
        reloadOverlay()
    }
}
