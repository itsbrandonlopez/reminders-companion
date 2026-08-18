import Observation
import RemindersCore
import SwiftUI

/// The phone's object graph.
///
/// Deliberately thinner than the Mac's `AppEnvironment`: no folders, no manual ordering,
/// no estimates. Those live in a local sidecar that does not sync, and the phone is a
/// companion rather than the place you organise from. Everything that matters on the road
/// — tasks, lists, planned days, deadlines — already arrives through iCloud Reminders.
@MainActor
@Observable
final class MobileEnvironment {
    let store: ReminderStore

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
        // The sidecar is unused on the phone but `ReminderStore` needs one for rank
        // seeding; an in-memory store avoids leaving a database behind for nothing.
        let meta = (try? MetaStore()) ?? (try! MetaStore(inMemory: true))
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

    /// Ordered by priority then day. The phone has no manual ordering to honour.
    var tasks: [TaskItem] {
        let active = activeListIDs
        return store.tasks
            .filter { active.contains($0.listID) && !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.priority.sortWeight != rhs.priority.sortWeight {
                    return lhs.priority.sortWeight < rhs.priority.sortWeight
                }
                return (lhs.boardDay ?? .today()) < (rhs.boardDay ?? .today())
            }
    }

    var week: [Day] { Scheduling.week(containing: weekAnchor) }

    private var currentWeekStart: Day {
        Scheduling.week(containing: .today()).first ?? .today()
    }

    /// Work that slipped past the whole of the current week. Same rule as the Mac.
    var backlog: [TaskItem] {
        let start = currentWeekStart
        return tasks.filter {
            Scheduling.bucket(
                plannedDay: $0.plannedDay, dueDay: $0.dueDay, currentWeekStart: start
            ) == .backlog
        }
        .sorted { ($0.boardDay ?? .today()) < ($1.boardDay ?? .today()) }
    }

    var unscheduled: [TaskItem] { tasks.filter(\.isBacklog) }

    private var triaged: Set<String> {
        Set(backlog.map(\.id)).union(unscheduled.map(\.id))
    }

    /// Only dated work, with the two piles held back so the day and week views stay clean.
    func tasks(on day: Day) -> [TaskItem] {
        let held = triaged
        return tasks.filter { $0.boardDay == day && !held.contains($0.id) }
    }

    var todaysTasks: [TaskItem] { tasks(on: .today()) }

    var pastDueCount: Int { backlog.count }

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
