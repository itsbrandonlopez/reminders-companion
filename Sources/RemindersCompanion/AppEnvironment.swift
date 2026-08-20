import Observation
import RemindersCore
import SwiftUI

/// Which column a new task is being typed into.
///
/// The + button is one button for every view, so where a task lands has to be a value
/// rather than a property of whichever field happened to have focus. Dropping the button
/// on a column sets this; the field appears wherever it points.
enum ComposeTarget: Hashable {
    /// A day column on the Week board — the task is planned for that day.
    case day(Day)
    /// The Week board's pool. Creates a task with no date at all.
    case unscheduled
    /// A list column on the Today board: that list, planned for today.
    case todayList(String)
    /// A list on its own. That list, no date — the same thing Reminders' new row does.
    case list(String)
    /// One column of a sectioned list. The task is filed into that section on creation;
    /// a nil section is the list's unsectioned column.
    case listSection(list: String, section: String?)
}

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

    /// Where the sidecar lives — synced, or on this Mac alone. Surfaced in the sidebar,
    /// because "my sections haven't appeared on my phone" has two very different causes
    /// and only one of them is a bug.
    private(set) var sidecarStorage: MetaStore.Storage = .local

    /// Convenience for setup: selects every list, i.e. clears the filter.
    func includeAllLists() { selectedListIDs.removeAll() }

    /// Which lists take part in the aggregate views. Empty means all of them.
    /// Driven by the checkmark menu, kept separate from `focus` so drilling into one
    /// list does not disturb the set you normally work with.
    var selectedListIDs: Set<String> = []
    var focus: SidebarFocus = .week {
        didSet {
            // A compose field belongs to the column it was opened in. Switching views
            // leaves it nowhere to live, so it closes rather than reappearing later in
            // a column the user has since navigated away from.
            if focus != oldValue { composeTarget = nil }
        }
    }
    var weekAnchor: Day = .today()
    var searchText: String = ""
    var isUnscheduledCollapsed = false

    /// The one column currently offering a field to type a new task into, if any.
    ///
    /// Single-valued on purpose: there is one + button, so there is one field. Before
    /// this, every column carried its own permanently visible add field, which put nine
    /// text fields on the week board competing for a click.
    private(set) var composeTarget: ComposeTarget?

    func beginCompose(_ target: ComposeTarget) {
        // A field inside a folded-away column would be typing into nothing.
        if target == .unscheduled { isUnscheduledCollapsed = false }
        composeTarget = target
    }

    /// Closes the field — but only if it is still the one asking. A drop that opens a
    /// second column while the first is losing focus must not have the first cancel the
    /// second on its way out.
    func endCompose(_ target: ComposeTarget) {
        if composeTarget == target { composeTarget = nil }
    }

    /// Where the + opens when it is clicked rather than dragged: whatever the view on
    /// screen most obviously means by "a new task".
    var defaultComposeTarget: ComposeTarget {
        switch focus {
        case let .list(id):
            // A sectioned list draws as columns, where the flat field has nowhere to
            // appear. The unsectioned column is where an unfiled task belongs anyway.
            return sections(in: id).isEmpty ? .list(id) : .listSection(list: id, section: nil)
        case .today:
            // The list Siri writes to, so a typed task and a voice capture land together.
            let target = visibleLists.first { $0.isDefault && $0.isEditable }
                ?? visibleLists.first(where: \.isEditable)
            return target.map { .todayList($0.id) } ?? .unscheduled
        case .week:
            // Adding while looking at another week defaults to that week's first day
            // rather than to today, so the task lands where you were looking.
            return .day(week.contains(.today()) ? .today() : (week.first ?? .today()))
        }
    }

    /// Creates what a compose field just submitted, in the column it belongs to.
    ///
    /// When the target names a list, that list wins over any `#list` token in the text —
    /// the column *is* the answer to which list. A day column claims no list, so the
    /// token still decides there.
    func commitCompose(_ input: String, in target: ComposeTarget) {
        switch target {
        case let .day(day): quickAdd(input, defaultDay: day)
        case .unscheduled: quickAdd(input, defaultDay: nil)
        case let .todayList(id): create(input, in: id, defaultDay: .today())
        case let .list(id): create(input, in: id, defaultDay: nil)
        case let .listSection(id, section):
            create(input, in: id, defaultDay: nil, sectionID: section)
        }
    }

    private func create(
        _ input: String, in listID: String, defaultDay: Day?, sectionID: String? = nil
    ) {
        let parsed = QuickAddParser.parse(input)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            let created = await store.create(
                title: title,
                in: listID,
                on: parsed.day ?? defaultDay,
                priority: parsed.priority ?? .none
            )
            // Filed after the fact, since the section lives in the sidecar and the
            // identifier to key it on only exists once Reminders has saved the reminder.
            if let sectionID, let created {
                store.setSections([created: sectionID])
            }
        }
    }

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

    /// Ordering for the Week board's backlog. Persisted — it is a working preference, not
    /// a per-session one.
    var backlogSort: BacklogSort = .oldestFirst {
        didSet { defaults.set(backlogSort.rawValue, forKey: Self.backlogSortKey) }
    }

    /// Ordering for the Today board's overdue pile. Separate from `backlogSort` because
    /// the two piles hold different sets — see `overdue`.
    var overdueSort: BacklogSort = .oldestFirst {
        didSet { defaults.set(overdueSort.rawValue, forKey: Self.overdueSortKey) }
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

    /// Whether the Today board's timeline rail is folded to a strip. Persisted, because
    /// whether you want your day's shape next to your day's work is a standing preference,
    /// not a per-session one.
    var isTimelineCollapsed: Bool {
        didSet { defaults.set(isTimelineCollapsed, forKey: Self.timelineCollapsedKey) }
    }

    private let defaults = UserDefaults.standard
    private static let overlayKey = "overlayCalendarIDs"
    private static let autoPickedKey = "didAutoPickWorkCalendar"
    private static let calendarsCollapsedKey = "isCalendarsCollapsed"
    private static let timelineCollapsedKey = "isTimelineCollapsed"
    private static let unscheduledKey = "unscheduledListIDs"
    private static let seededFoldersKey = "didSeedFolders"
    private static let backlogSortKey = "backlogSort"
    private static let overdueSortKey = "overdueSort"
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
        self.sidecarStorage = meta.storage
        self.sidecarWarning = warning
        self.isCalendarsCollapsed = defaults.bool(forKey: Self.calendarsCollapsedKey)
        self.isTimelineCollapsed = defaults.bool(forKey: Self.timelineCollapsedKey)
        self.overlayCalendarIDs = Set(defaults.stringArray(forKey: Self.overlayKey) ?? [])
        self.unscheduledListIDs = Set(defaults.stringArray(forKey: Self.unscheduledKey) ?? [])
        self.backlogSort = BacklogSort(rawValue: defaults.string(forKey: Self.backlogSortKey) ?? "")
            ?? .oldestFirst
        self.overdueSort = BacklogSort(rawValue: defaults.string(forKey: Self.overdueSortKey) ?? "")
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

    var week: [Day] { Scheduling.week(containing: weekAnchor) }

    // MARK: - Derived slices
    //
    // Everything the boards read is derived from `store.tasks`, and none of it used to be
    // cached. SwiftUI reads these repeatedly within a single body evaluation — `DayColumn`
    // touches `tasks(on:)` four times, and each of those re-derived `backlog`, which
    // re-derived `filteredTasks`, which filters and sorts the whole array. One render of
    // the week board came to roughly 95 full traversals and 40 sorts.
    //
    // So they are computed together, once, behind a key naming everything they depend on.
    // The key is all cheap scalars and sets, and reading it touches the same observable
    // properties the old code did — so SwiftUI still invalidates exactly when it should.

    private struct SliceKey: Equatable {
        let dataRevision: Int
        let focus: SidebarFocus
        let selectedListIDs: Set<String>
        let unscheduledListIDs: Set<String>
        let searchText: String
        let backlogSort: BacklogSort
        let overdueSort: BacklogSort
        let weekAnchor: Day
        /// The board's idea of "now". Rolls the cache over at midnight rather than leaving
        /// yesterday's buckets on screen.
        let today: Day
    }

    private struct Slices {
        var filtered: [TaskItem] = []
        var backlog: [TaskItem] = []
        var backlogIDs: Set<String> = []
        var overdue: [TaskItem] = []
        var unscheduled: [TaskItem] = []
        /// Tasks sitting on a day, backlog excluded.
        var byDay: [Day: [TaskItem]] = [:]
        /// Tasks whose span passes *through* a day without starting on it. Built only for
        /// the visible week — a span can be arbitrarily long, and no other day is drawn.
        var continuingByDay: [Day: [TaskItem]] = [:]
        var todayCount = 0
        var scheduledCount = 0
        var countByList: [String: Int] = [:]
    }

    // Not observed: this is a memo of observable state, not state of its own. Observing it
    // would loop, since it is written from inside the getters that read it.
    @ObservationIgnored private var cacheKey: SliceKey?
    @ObservationIgnored private var cache = Slices()

    private var slices: Slices {
        let key = SliceKey(
            dataRevision: store.dataRevision,
            focus: focus,
            selectedListIDs: selectedListIDs,
            unscheduledListIDs: unscheduledListIDs,
            searchText: searchText,
            backlogSort: backlogSort,
            overdueSort: overdueSort,
            weekAnchor: weekAnchor,
            today: .today()
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
        let search = key.searchText
        let today = key.today
        // The Monday of the week containing *today*, not the week being displayed. The
        // backlog is anchored to real time rather than to navigation, so paging forward to
        // plan next week does not suddenly sweep this week's work into it.
        let weekStart = Scheduling.week(containing: today).first ?? today

        // Tasks after list-filter and search, in manual order.
        //
        // Rank alone: it is seeded from priority on first sight, so an untouched board
        // still reads high-priority-first, but a manual reorder is never undone by a
        // re-fetch.
        out.filtered = store.tasks
            .filter { active.contains($0.listID) }
            .filter {
                search.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.notes ?? "").localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.rank < $1.rank }

        var backlog: [TaskItem] = []
        var overdue: [TaskItem] = []
        for task in out.filtered {
            if !task.isBacklog { out.scheduledCount += 1 }

            guard !task.isCompleted else { continue }

            if task.isOverdue(asOf: today) || (task.span?.contains(today) ?? false) {
                out.todayCount += 1
            }
            if let day = task.boardDay, day < today { overdue.append(task) }

            switch Scheduling.bucket(
                plannedDay: task.plannedDay, dueDay: task.dueDay, currentWeekStart: weekStart
            ) {
            case .backlog:
                backlog.append(task)
            case .unscheduled:
                if key.unscheduledListIDs.isEmpty || key.unscheduledListIDs.contains(task.listID) {
                    out.unscheduled.append(task)
                }
            case .day:
                break
            }
        }

        out.backlog = key.backlogSort.sort(backlog)
        out.overdue = key.overdueSort.sort(overdue)
        out.backlogIDs = Set(backlog.map(\.id))

        // Day buckets, in the same order `filtered` already has.
        for task in out.filtered where !out.backlogIDs.contains(task.id) {
            if let day = task.boardDay { out.byDay[day, default: []].append(task) }
        }
        for day in Scheduling.week(containing: key.weekAnchor) {
            let passing = out.filtered.filter { task in
                guard !out.backlogIDs.contains(task.id), let span = task.span else { return false }
                return span.contains(day) && task.boardDay != day
            }
            if !passing.isEmpty { out.continuingByDay[day] = passing }
        }

        // Sidebar list counts run over *every* task, not the filtered set — the number
        // beside a list should not change because you typed in the search box.
        for task in store.tasks { out.countByList[task.listID, default: 0] += 1 }

        return out
    }

    /// Tasks after list-filter and search, in manual order.
    var filteredTasks: [TaskItem] { slices.filtered }

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

    /// Dated work that slipped past the current week entirely.
    ///
    /// Something due this Monday when today is Tuesday is not backlog — it stays on
    /// Monday, where its column still reads as part of the week in progress. Only once
    /// the whole week has rolled past does it fall out into the backlog.
    var backlog: [TaskItem] { slices.backlog }

    /// Dated work whose day has already gone — a missed deadline, or something planned for
    /// a day now past.
    ///
    /// Deliberately **not** the same set as `backlog`, and the distinction is the point.
    /// The Week board leaves something due this Monday sitting on Monday when today is
    /// Tuesday, because the week in progress can still absorb it, and only sweeps up work
    /// that slipped past the whole week. A Today board cannot do that: anything whose day
    /// has gone has to resurface today or it is invisible. Two questions, so two names and
    /// two sort preferences — one control governing both would be one control governing
    /// two different sets.
    var overdue: [TaskItem] { slices.overdue }

    func tasks(on day: Day) -> [TaskItem] { slices.byDay[day] ?? [] }

    /// Multi-day tasks that pass *through* a day without starting on it, so a column can
    /// show them as continuation chips rather than losing them.
    func continuing(on day: Day) -> [TaskItem] { slices.continuingByDay[day] ?? [] }

    /// Tasks carrying no date at all — the pool you pull from when planning a week,
    /// narrowed to the lists you actually plan out of.
    var unscheduled: [TaskItem] { slices.unscheduled }

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

    // MARK: - Sections

    /// Bumped after every section mutation, for the same reason `folderRevision` exists:
    /// SwiftData models are not observed by this type.
    private(set) var sectionRevision = 0

    /// The sections of one list, in display order. Empty means the list has none, which is
    /// what makes it render flat rather than as columns.
    func sections(in listID: String) -> [ListSection] {
        _ = sectionRevision
        return meta.sections(in: listID)
    }

    func createSection(named name: String, in listID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        meta.createSection(named: trimmed, in: listID)
        sectionRevision += 1
    }

    func rename(_ section: ListSection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        section.name = trimmed
        meta.save()
        sectionRevision += 1
    }

    /// Deleting a section returns its tasks to the unsectioned column. Nothing in
    /// Reminders is touched.
    func delete(_ section: ListSection) {
        if composeTarget == .listSection(list: section.listID, section: section.id.uuidString) {
            composeTarget = nil
        }
        meta.deleteSection(section)
        sectionRevision += 1
        store.reloadSidecar()
    }

    /// Shuffles a section one place left or right.
    func move(_ section: ListSection, by offset: Int) {
        var ordered = meta.sections(in: section.listID)
        guard let index = ordered.firstIndex(where: { $0.id == section.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        meta.reorderSections(ordered)
        sectionRevision += 1
    }

    // MARK: - Sidebar counts

    /// Everything owed today, matching what the Today board shows.
    var todayCount: Int { slices.todayCount }
    var scheduledCount: Int { slices.scheduledCount }

    func count(for list: TaskList) -> Int { slices.countByList[list.id] ?? 0 }
}
