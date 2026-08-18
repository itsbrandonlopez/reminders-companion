import Observation
import RemindersCore
import SwiftUI

/// Owns the object graph for the window. Kept separate from `ReminderStore` so the
/// store stays focused on EventKit and testable without any UI around it.
@MainActor
@Observable
final class AppEnvironment {
    let store: ReminderStore
    /// Surfaced in the UI: the sidecar failing is survivable (ordering and estimates are
    /// lost, tasks are not), so the app falls back to an in-memory store rather than
    /// refusing to launch.
    private(set) var sidecarWarning: String?

    /// Convenience for setup: selects every list, i.e. clears the filter.
    func includeAllLists() { selectedListIDs.removeAll() }

    /// Which lists take part in the aggregate views. Empty means all of them.
    /// Driven by the checkmark menu, kept separate from `focus` so drilling into one
    /// list does not disturb the set you normally work with.
    var selectedListIDs: Set<String> = []
    var focus: SidebarFocus = .scheduled
    var weekAnchor: Day = .today()
    var searchText: String = ""
    var isUnscheduledCollapsed = false

    /// Pending demo-data action awaiting confirmation. Writing to someone's Reminders is
    /// never done off a bare menu click.
    enum SampleAction: Identifiable {
        case install, remove
        var id: Int { self == .install ? 0 : 1 }
    }
    var pendingSampleAction: SampleAction?

    /// Whether first-run setup has been completed. Persisted, so setup is a one-time
    /// experience rather than a gate the app re-litigates on every launch.
    private(set) var hasCompletedSetup: Bool = false

    func completeSetup() {
        hasCompletedSetup = true
        defaults.set(true, forKey: Self.setupCompleteKey)
    }

    /// Runs setup again from the beginning. Reachable from the Help menu, mostly so the
    /// flow can be shown to someone else without wiping preferences.
    func restartSetup() {
        hasCompletedSetup = false
        defaults.set(false, forKey: Self.setupCompleteKey)
    }

    /// Which calendars the overlay draws. Persisted, because re-picking your work
    /// calendar on every launch would make the feature not worth using.
    var overlayCalendarIDs: Set<String> = [] {
        didSet {
            defaults.set(Array(overlayCalendarIDs), forKey: Self.overlayKey)
            reloadOverlay()
        }
    }

    /// Ordering for both backlogs. Persisted — it is a working preference, not a
    /// per-session one.
    var backlogSort: BacklogSort = .oldestFirst {
        didSet { defaults.set(backlogSort.rawValue, forKey: Self.backlogSortKey) }
    }

    /// Which lists feed the Unscheduled column. Empty means all of them.
    ///
    /// Separate from `selectedListIDs` on purpose: the pool you plan a week from is not
    /// the same question as which lists the board shows. A big archival list can be kept
    /// out of Unscheduled while its dated tasks still appear on their days.
    var unscheduledListIDs: Set<String> = [] {
        didSet { defaults.set(Array(unscheduledListIDs), forKey: Self.unscheduledKey) }
    }

    /// Whether the Calendars section is folded away. Persisted so the sidebar opens the
    /// way you left it.
    var isCalendarsCollapsed: Bool {
        didSet { defaults.set(isCalendarsCollapsed, forKey: Self.calendarsCollapsedKey) }
    }

    private let defaults = UserDefaults.standard
    private static let overlayKey = "overlayCalendarIDs"
    private static let autoPickedKey = "didAutoPickWorkCalendar"
    private static let calendarsCollapsedKey = "isCalendarsCollapsed"
    private static let unscheduledKey = "unscheduledListIDs"
    private static let seededFoldersKey = "didSeedFolders"
    private static let backlogSortKey = "backlogSort"
    private static let setupCompleteKey = "hasCompletedSetup"

    /// Held so the sidebar can read and mutate folders. Folders are sidecar-only: the
    /// Reminders folder hierarchy is not exposed by any API. See `ListFolder`.
    private let meta: MetaStore

    init() {
        let meta: MetaStore
        var warning: String?
        do {
            meta = try MetaStore()
        } catch {
            warning = "Ordering and estimates won't be saved this session: \(error.localizedDescription)"
            meta = try! MetaStore(inMemory: true)
        }
        self.meta = meta
        self.store = ReminderStore(meta: meta)
        self.sidecarWarning = warning
        self.isCalendarsCollapsed = defaults.bool(forKey: Self.calendarsCollapsedKey)
        self.overlayCalendarIDs = Set(defaults.stringArray(forKey: Self.overlayKey) ?? [])
        self.unscheduledListIDs = Set(defaults.stringArray(forKey: Self.unscheduledKey) ?? [])
        self.backlogSort = BacklogSort(rawValue: defaults.string(forKey: Self.backlogSortKey) ?? "")
            ?? .oldestFirst
        self.hasCompletedSetup = defaults.bool(forKey: Self.setupCompleteKey)
    }

    /// The lists currently on screen: one when drilled in, otherwise the checked set.
    var activeListIDs: Set<String> {
        if case let .list(id) = focus { return [id] }
        return selectedListIDs.isEmpty ? Set(store.lists.map(\.id)) : selectedListIDs
    }

    var visibleLists: [TaskList] {
        let active = activeListIDs
        return store.lists.filter { active.contains($0.id) }
    }

    /// Tasks after list-filter and search, in manual order.
    var filteredTasks: [TaskItem] {
        let active = activeListIDs
        return store.tasks
            .filter { active.contains($0.listID) }
            .filter {
                searchText.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.notes ?? "").localizedCaseInsensitiveContains(searchText)
            }
            // Rank alone: it is seeded from priority on first sight, so an untouched
            // board still reads high-priority-first, but a manual reorder is never
            // undone by a re-fetch.
            .sorted { $0.rank < $1.rank }
    }

    var week: [Day] { Scheduling.week(containing: weekAnchor) }

    // MARK: - Calendar overlay

    /// Switches the overlay on, prompting for Calendar access the first time.
    ///
    /// Only ever called from an explicit user action. The overlay is optional, and the
    /// app should never open by asking for a second permission it may not need.
    /// On first enable it picks a calendar named "Work" if there is one, so the common
    /// case needs no configuration.
    func enableOverlay() async {
        if store.eventAccess == .notDetermined {
            await store.requestEventAccess()
        }
        guard store.eventAccess == .granted else { return }
        store.refreshCalendars()

        if !defaults.bool(forKey: Self.autoPickedKey) {
            defaults.set(true, forKey: Self.autoPickedKey)
            if overlayCalendarIDs.isEmpty,
               let work = store.calendars.first(where: { $0.title.localizedCaseInsensitiveContains("work") }) {
                overlayCalendarIDs = [work.id]
                return   // the didSet already reloaded
            }
        }
        reloadOverlay()
    }

    /// Restores a previously configured overlay at launch without ever prompting.
    func loadOverlayIfAuthorized() {
        guard store.eventAccess == .granted else { return }
        store.refreshCalendars()
        reloadOverlay()
    }

    /// Loads events for the visible week plus a day of slack on each side, so an event
    /// that starts late Sunday and runs into Monday still resolves.
    func reloadOverlay() {
        guard let first = week.first, let last = week.last else { return }
        store.refreshEvents(
            from: first.adding(days: -1).startOfDay(),
            to: last.adding(days: 2).startOfDay(),
            calendarIDs: overlayCalendarIDs
        )
    }

    func events(on day: Day) -> [CalendarEvent] {
        store.events.filter { $0.occupies(day) }
    }

    /// Total booked time on a day, used to answer "is Thursday already spoken for?"
    /// All-day events are excluded — they have no duration to add up.
    func bookedMinutes(on day: Day) -> Int {
        events(on: day).filter { !$0.isAllDay }.reduce(0) { $0 + $1.durationMinutes }
    }

    /// The Monday of the week containing *today* — not the week being displayed.
    ///
    /// The backlog is anchored to real time rather than to navigation, so paging forward
    /// to plan next week does not suddenly sweep this week's work into it.
    private var currentWeekStart: Day {
        Scheduling.week(containing: .today()).first ?? .today()
    }

    /// Dated work that slipped past the current week entirely.
    ///
    /// Something due this Monday when today is Tuesday is not backlog — it stays on
    /// Monday, where its column still reads as part of the week in progress. Only once
    /// the whole week has rolled past does it fall out into the backlog.
    var backlog: [TaskItem] {
        let start = currentWeekStart
        return sortedByAge(filteredTasks.filter { task in
            guard !task.isCompleted else { return false }
            return Scheduling.bucket(
                plannedDay: task.plannedDay, dueDay: task.dueDay, currentWeekStart: start
            ) == .backlog
        })
    }

    func sortedByAge(_ tasks: [TaskItem]) -> [TaskItem] { backlogSort.sort(tasks) }

    private var backlogIDs: Set<String> { Set(backlog.map(\.id)) }

    func tasks(on day: Day) -> [TaskItem] {
        let excluded = backlogIDs
        return filteredTasks.filter { $0.boardDay == day && !excluded.contains($0.id) }
    }

    /// Multi-day tasks that pass *through* a day without starting on it, so a column can
    /// show them as continuation chips rather than losing them.
    func continuing(on day: Day) -> [TaskItem] {
        let excluded = backlogIDs
        return filteredTasks.filter { task in
            guard let span = task.span, span.contains(day) else { return false }
            return task.boardDay != day && !excluded.contains(task.id)
        }
    }

    /// Tasks carrying no date at all — the pool you pull from when planning a week,
    /// narrowed to the lists you actually plan out of.
    var unscheduled: [TaskItem] {
        let allowed = unscheduledListIDs
        return filteredTasks.filter {
            $0.isBacklog && (allowed.isEmpty || allowed.contains($0.listID))
        }
    }

    func jumpWeek(_ delta: Int) {
        weekAnchor = weekAnchor.adding(days: delta * 7)
        reloadOverlay()
    }

    func goToToday() {
        weekAnchor = .today()
        reloadOverlay()
    }

    /// Creates a task from raw quick-add text, honouring any `!` priority, `#list` and
    /// natural-language date it contains.
    ///
    /// `defaultDay` is what the column implies — Thursday's column passes Thursday, the
    /// unscheduled pool passes nil. An explicit date in the text overrides it, because
    /// typing "tomorrow" is a deliberate act and the column is merely where the cursor
    /// happened to be.
    func quickAdd(_ input: String, defaultDay: Day?) {
        let parsed = QuickAddParser.parse(input)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let listID = parsed.listToken
            .flatMap { QuickAddParser.matchList($0, in: store.lists.filter(\.isEditable))?.id }
            // Default to the list Siri writes to, so quick-add and voice capture land in
            // the same place.
            ?? visibleLists.first(where: \.isDefault)?.id
            ?? visibleLists.first(where: \.isEditable)?.id
        guard let listID else { return }

        Task {
            await store.create(
                title: title,
                in: listID,
                on: parsed.day ?? defaultDay,
                priority: parsed.priority ?? .none
            )
        }
    }

    // MARK: - Folders

    /// Bumped after every folder mutation so `@Observable` re-renders the sidebar.
    /// SwiftData models are not themselves observed by this type.
    private(set) var folderRevision = 0

    var folders: [ListFolder] {
        _ = folderRevision
        return meta.folders()
    }

    /// Lists not filed into any folder, shown beneath the folders exactly as Reminders does.
    var ungroupedLists: [TaskList] {
        let filed = Set(folders.flatMap(\.listIDs))
        return store.lists.filter { !filed.contains($0.id) }
    }

    func lists(in folder: ListFolder) -> [TaskList] {
        // Preserve the folder's own ordering, and skip ids whose list has since vanished.
        folder.listIDs.compactMap { id in store.lists.first { $0.id == id } }
    }

    func count(in folder: ListFolder) -> Int {
        lists(in: folder).reduce(0) { $0 + count(for: $1) }
    }

    /// Creates the two folders the user already keeps in Reminders, once, so the sidebar
    /// starts from something familiar rather than empty. Deleting them sticks.
    func seedFoldersIfNeeded() {
        guard !defaults.bool(forKey: Self.seededFoldersKey) else { return }
        defaults.set(true, forKey: Self.seededFoldersKey)
        guard meta.folders().isEmpty else { return }
        meta.createFolder(named: "Personal")
        meta.createFolder(named: "Work")
        folderRevision += 1
    }

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        meta.createFolder(named: trimmed)
        folderRevision += 1
    }

    func rename(_ folder: ListFolder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        meta.save()
        folderRevision += 1
    }

    /// Deleting a folder only ungroups its lists — it never touches Reminders.
    func delete(_ folder: ListFolder) {
        meta.deleteFolder(folder)
        folderRevision += 1
    }

    func assign(listID: String, to folder: ListFolder?) {
        meta.assign(listID: listID, to: folder)
        folderRevision += 1
    }

    func toggleCollapsed(_ folder: ListFolder) {
        folder.isCollapsed.toggle()
        meta.save()
        folderRevision += 1
    }

    // MARK: - Sidebar counts

    /// Everything owed today, matching what the Today board shows.
    var todayCount: Int {
        let today = Day.today()
        return filteredTasks.filter { task in
            guard !task.isCompleted else { return false }
            if task.isOverdue() { return true }
            if let span = task.span { return span.contains(today) }
            return false
        }.count
    }

    var scheduledCount: Int { filteredTasks.filter { !$0.isBacklog }.count }
    var allCount: Int { filteredTasks.count }

    func count(for list: TaskList) -> Int {
        store.tasks.filter { $0.listID == list.id }.count
    }
}
