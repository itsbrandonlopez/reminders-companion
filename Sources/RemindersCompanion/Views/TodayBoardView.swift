import RemindersCore
import SwiftUI

/// Today, split kanban-style with one column per Reminders list.
///
/// Lists are the only grouping dimension EventKit exposes — tags, flags and sections are
/// absent from the API — but they map cleanly onto client work, which is how the columns
/// are meant to read.
struct TodayBoardView: View {
    @Environment(AppEnvironment.self) private var env

    private var today: Day { .today() }

    /// Anything whose day has already gone by — a missed deadline, or work planned for a
    /// day that has passed. Both need to resurface today, and neither belongs in a client
    /// column where it would read as today's work.
    ///
    /// This is `env.overdue`, not `env.backlog`: the Week board's backlog holds only work
    /// that slipped past the *whole* current week, which on a Tuesday would leave Monday's
    /// missed deadline showing nowhere on this screen.
    private var overdue: [TaskItem] { env.overdue }

    /// Today's actual work. Overdue items are pulled out into their own column, so a
    /// client column shows only what is genuinely due today.
    private var todaysTasks: [TaskItem] {
        let stale = Set(overdue.map(\.id))
        return env.filteredTasks.filter { task in
            guard !task.isCompleted, !stale.contains(task.id) else { return false }
            guard let span = task.span else { return false }
            return span.contains(today)
        }
    }

    private var columns: [TaskList] {
        var populated = Set(todaysTasks.map(\.listID))
        // A column opened for typing has to be on screen even when nothing is due in it
        // today, or the + would drop into a list that vanishes under the cursor.
        if case let .todayList(id) = env.composeTarget { populated.insert(id) }
        return env.visibleLists.filter { populated.contains($0.id) || $0.isDefault }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.separator)
            // The timeline sits outside the horizontal scroll view, so scrolling to the
            // fifth client column never scrolls the day's shape off the screen.
            HStack(spacing: 0) {
                work
                if showsTimeline {
                    Divider().overlay(Palette.separator)
                    DayTimelineView(day: today, events: env.events(on: today))
                }
            }
        }
    }

    /// Whether the day's calendar is worth a rail at all.
    ///
    /// Tied to having picked calendars rather than to having events: an empty grid with a
    /// now-line says "the rest of today is yours", which is worth knowing, but someone who
    /// never switched the overlay on should not be given a column about it.
    private var showsTimeline: Bool {
        env.store.eventAccess == .granted && !env.overlayCalendarIDs.isEmpty
    }

    @ViewBuilder private var work: some View {
        if columns.isEmpty && overdue.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.textTertiary)
                Text("Nothing due today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Drag work in from the Week view when you're ready for it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.window)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.gutter) {
                    ForEach(columns) { list in
                        ListColumn(list: list, tasks: todaysTasks.filter { $0.listID == list.id })
                    }
                    if !overdue.isEmpty {
                        TodayOverdueColumn(tasks: overdue)
                    }
                }
                .padding(Metrics.gutter)
            }
            .background(Palette.window)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(today.monthDayLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("\(todaysTasks.count) task\(todaysTasks.count == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if !overdue.isEmpty {
                Text("\(overdue.count) past due")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.overdue)
            }
            if env.bookedMinutes(on: today) > 0 {
                let m = env.bookedMinutes(on: today)
                Text(m >= 60 ? String(format: "%.1fh booked", Double(m) / 60) : "\(m)m booked")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            if env.store.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Palette.window)
    }
}

/// A single client column. Dropping here reassigns the task's Reminders list, which is a
/// real move in Reminders — not a view-only regrouping.
struct ListColumn: View {
    let list: TaskList
    let tasks: [TaskItem]

    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false

    var body: some View {
        BoardColumn(tint: Color(list.color).opacity(0.08), isTargeted: isTargeted) {
            HStack(spacing: 6) {
                Circle().fill(Color(list.color)).frame(width: 7, height: 7)
                Text(list.title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .lineLimit(1)
                Spacer()
                if !tasks.isEmpty { Text("\(tasks.count)").font(.system(size: 10.5)) }
            }
            .foregroundStyle(Palette.textSecondary)
        } content: {
            ForEach(tasks) { task in
                TaskCardView(task: task, onNewTaskDrop: { compose() })
                    .draggable(task.id)
            }
            if tasks.isEmpty { EmptyHint(text: "Clear") }
        } footer: {
            if env.composeTarget == .todayList(list.id) {
                ComposeField(target: .todayList(list.id), placeholder: "New task in \(list.title)")
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let raw = ids.first else { return false }
            switch DragPayload.kind(raw) {
            case .newTask:
                return compose()
            case .span:
                // A span is a range of days. This column is a list, not a day.
                return false
            case let .task(id):
                guard let task = env.store.tasks.first(where: { $0.id == id }),
                      task.listID != list.id else { return false }
                Task { await env.store.move(task, toList: list.id) }
                return true
            }
        } isTargeted: { isTargeted = $0 }
    }

    /// Opens the compose field in this list. Read-only lists — Siri's suggestions, a
    /// subscribed calendar — cannot take a new task, so the drop is refused instead.
    private func compose() -> Bool {
        guard list.isEditable else { return false }
        env.beginCompose(.todayList(list.id))
        return true
    }
}


/// Everything whose day has gone, in one vertical rather than split by client.
///
/// Deliberately not broken into list columns: overdue work is a single pile you triage
/// top to bottom, and splitting it across five columns is what let it slip in the first
/// place.
///
/// Named Overdue rather than Backlog because it is a different set from the Week board's
/// Backlog column — see `AppEnvironment.overdue`. `tasks` arrives already ordered by
/// `overdueSort`.
struct TodayOverdueColumn: View {
    let tasks: [TaskItem]
    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false

    var body: some View {
        @Bindable var env = env
        return BoardColumn(tint: Palette.overdue.opacity(0.08), isTargeted: isTargeted) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                Text("OVERDUE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                Spacer()
                AgeSortMenu(sort: $env.overdueSort, help: "Sort overdue")
                Text("\(tasks.count)").font(.system(size: 10.5))
            }
            .foregroundStyle(Palette.overdue)
        } content: {
            ForEach(tasks) { task in
                TaskCardView(task: task).draggable(task.id)
            }
        } footer: {
            // One tap to sweep the whole pile onto today, which is the usual answer.
            Button {
                // Batched: the per-task path would commit and refetch once per item.
                Task { await env.store.schedule(tasks, to: .today()) }
            } label: {
                Text("Move All to Today")
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
            )
        }
        .dropDestination(for: String.self) { _, _ in
            // Overdue membership is derived from dates already past, not a state you can
            // assign — and there is no such thing as a new task that is already late — so
            // neither a card nor the + has anything to write here.
            false
        } isTargeted: { isTargeted = $0 }
    }
}
