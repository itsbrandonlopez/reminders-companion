import RemindersCore
import SwiftUI

struct WeekBoardView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            Divider().overlay(Palette.separator)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.gutter) {
                    UnscheduledColumn()
                    ForEach(env.week, id: \.self) { day in
                        DayColumn(day: day)
                    }
                    BacklogColumn()
                }
                .padding(Metrics.gutter)
            }
            .background(Palette.window)
        }
    }

    private var weekHeader: some View {
        HStack(spacing: 10) {
            Button { env.jumpWeek(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
            }
            Button("Today") { env.goToToday() }
                .font(.system(size: 12))
            Button { env.jumpWeek(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }

            Text(weekLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.leading, 4)

            Spacer()

            if !env.backlog.isEmpty {
                Text("\(env.backlog.count) in backlog")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.overdue)
            }
            if env.store.isLoading { ProgressView().controlSize(.small) }
        }
        .buttonStyle(.borderless)
        .tint(Palette.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Palette.window)
    }

    private var weekLabel: String {
        guard let first = env.week.first, let last = env.week.last else { return "" }
        return "\(first.monthDayLabel) – \(last.monthDayLabel)"
    }
}

/// Shared column chrome so every column reads as the same object.
struct BoardColumn<Header: View, Content: View, Footer: View>: View {
    var tint: Color = Palette.column
    var width: CGFloat = Metrics.columnWidth
    var isTargeted: Bool
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header.padding(.horizontal, 4)
            ScrollView {
                LazyVStack(spacing: 7) { content }
                    .padding(.horizontal, 1)
            }
            footer
        }
        .padding(10)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Metrics.columnCorner, style: .continuous).fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.columnCorner, style: .continuous)
                .strokeBorder(isTargeted ? Palette.accent : .clear, lineWidth: 2)
        )
    }
}

struct ColumnHeader: View {
    let title: String
    var symbol: String?
    var count: Int
    var accent: Color = Palette.textSecondary
    var trailing: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10))
            }
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 10.5, weight: .medium))
            }
            if count > 0 {
                Text("\(count)").font(.system(size: 10.5))
            }
        }
        .foregroundStyle(accent)
    }
}

/// One day of the week. Dropping here writes only `startDateComponents` — the deadline
/// and any alarms on the reminder are left exactly as they were.
struct DayColumn: View {
    let day: Day
    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false

    private var tasks: [TaskItem] { env.tasks(on: day) }
    private var continuing: [TaskItem] { env.continuing(on: day) }

    var body: some View {
        BoardColumn(
            tint: day.isToday ? Palette.accent.opacity(0.09) : Palette.column,
            isTargeted: isTargeted
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(day.shortWeekday.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(day.isToday ? Palette.accent : Palette.textSecondary)
                Text(day.dayNumber)
                    .font(.system(size: 16, weight: day.isToday ? .semibold : .regular))
                    .foregroundStyle(
                        day.isToday ? Palette.accent
                            : (day.isPast ? Palette.textTertiary : Palette.textPrimary)
                    )
                Spacer()
                if let booked = bookedLabel {
                    Text(booked)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(Palette.accent.opacity(0.16))
                        )
                        .help("Booked in your calendars")
                }
                if let load = estimatedLoad {
                    Text(load)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        } content: {
            let events = env.events(on: day)
            if !events.isEmpty {
                ForEach(events) { event in
                    EventChip(event: event, day: day)
                }
                Divider()
                    .overlay(Palette.separator)
                    .padding(.vertical, 2)
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskCardView(
                    task: task,
                    showsSpanHandle: true,
                    onDropAbove: { droppedID in insert(droppedID, above: index) },
                    onSpanDrop: { draggedID in extendSpan(draggedID) },
                    onNewTaskDrop: { compose() }
                )
                .draggable(task.id)
            }
            ForEach(continuing) { task in
                TaskCardView(
                    task: task, isContinuation: true, showsSpanHandle: true,
                    onNewTaskDrop: { compose() }
                )
            }
            if tasks.isEmpty && continuing.isEmpty && events.isEmpty {
                EmptyHint(text: "Nothing planned")
            }
        } footer: {
            if env.composeTarget == .day(day) { ComposeField(target: .day(day)) }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let raw = ids.first else { return false }
            switch DragPayload.kind(raw) {
            case .newTask:
                return compose()
            case let .span(id):
                // The grab handle stretches the task's far end to this day.
                guard let task = env.store.tasks.first(where: { $0.id == id }) else { return false }
                Task { await env.store.setSpanEnd(task, to: day) }
                return true
            case let .task(id):
                // The card body moves the whole task here.
                guard let task = env.store.tasks.first(where: { $0.id == id }) else { return false }
                Task { await env.store.schedule(task, to: day) }
                return true
            }
        } isTargeted: { isTargeted = $0 }
    }

    /// Opens the compose field on this day. Returns true so the drop reads as accepted —
    /// nothing was written, but something did happen.
    private func compose() -> Bool {
        env.beginCompose(.day(day))
        return true
    }

    /// Places the dragged task immediately above the card at `index`, scheduling it onto
    /// this day first if it came from another column.
    private func insert(_ droppedID: String, above index: Int) -> Bool {
        // `tasks` is recomputed on every access, so a background refresh between render
        // and drop can shrink it out from under the captured index.
        let column = tasks
        guard index < column.count,
              let dragged = env.store.tasks.first(where: { $0.id == droppedID }) else { return false }
        let above = index > 0 ? column[index - 1] : nil
        let below = column[index]
        // Rank first: it is a synchronous sidecar write, so the order is already correct
        // by the time the reminder save triggers a refetch.
        env.store.reorder(dragged, above: above, below: below, within: column)
        if dragged.boardDay != day {
            Task { await env.store.schedule(dragged, to: day) }
        }
        return true
    }

    /// Cards sit on top of the column's own drop area, so a span dropped onto one has to
    /// be handled here rather than falling through to the column.
    private func extendSpan(_ draggedID: String) -> Bool {
        guard let task = env.store.tasks.first(where: { $0.id == draggedID }) else { return false }
        Task { await env.store.setSpanEnd(task, to: day) }
        return true
    }

    /// Hours already committed on the calendar. This is the number that decides whether
    /// a day can absorb more work.
    private var bookedLabel: String? {
        let minutes = env.bookedMinutes(on: day)
        guard minutes > 0 else { return nil }
        return minutes >= 60 ? String(format: "%.1fh", Double(minutes) / 60) : "\(minutes)m"
    }

    /// Total estimate of planned tasks, separate from calendar commitments.
    private var estimatedLoad: String? {
        let total = tasks.compactMap(\.estimateMinutes).reduce(0, +)
        guard total > 0 else { return nil }
        return total >= 60 ? String(format: "%.1fh", Double(total) / 60) : "\(total)m"
    }
}

/// Tasks carrying no date at all — the pool you pull from when planning the week.
/// Collapsible, because most of the time you want the week itself to have the room.
struct UnscheduledColumn: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false

    var body: some View {
        Group {
            if env.isUnscheduledCollapsed { collapsed } else { expanded }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let raw = ids.first else { return false }
            switch DragPayload.kind(raw) {
            case .newTask:
                return compose()
            case .span:
                // A span has to end on a day; there is nothing to stretch to here.
                return false
            case let .task(id):
                guard let task = env.store.tasks.first(where: { $0.id == id }) else { return false }
                // Clears the planned day only. A task with a real deadline keeps it, and
                // keeps showing up under that deadline.
                Task { await env.store.schedule(task, to: nil) }
                return true
            }
        } isTargeted: { isTargeted = $0 }
    }

    /// Opens the compose field here. Also unfolds the column, since the + can be dropped
    /// on it while it is collapsed.
    private func compose() -> Bool {
        withAnimation(.easeInOut(duration: 0.18)) { env.beginCompose(.unscheduled) }
        return true
    }

    private var expanded: some View {
        BoardColumn(isTargeted: isTargeted) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { env.isUnscheduledCollapsed = true }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Collapse")

                Text("UNSCHEDULED")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                Spacer()
                UnscheduledFilterMenu()
                Text("\(env.unscheduled.count)").font(.system(size: 10.5))
            }
            .foregroundStyle(Palette.textSecondary)
        } content: {
            ForEach(Array(env.unscheduled.enumerated()), id: \.element.id) { index, task in
                TaskCardView(
                    task: task,
                    onDropAbove: { droppedID in insert(droppedID, above: index) },
                    onNewTaskDrop: { compose() }
                )
                .draggable(task.id)
            }
            if env.unscheduled.isEmpty {
                EmptyHint(text: "Nothing waiting")
            }
        } footer: {
            if env.composeTarget == .unscheduled { ComposeField(target: .unscheduled) }
        }
    }

    /// Reordering the unscheduled pool. A task dropped in from a day column is
    /// unscheduled as part of the move.
    private func insert(_ droppedID: String, above index: Int) -> Bool {
        let pool = env.unscheduled
        guard index < pool.count,
              let dragged = env.store.tasks.first(where: { $0.id == droppedID }) else { return false }
        env.store.reorder(
            dragged, above: index > 0 ? pool[index - 1] : nil, below: pool[index], within: pool
        )
        if !dragged.isBacklog {
            Task { await env.store.schedule(dragged, to: nil) }
        }
        return true
    }

    private var collapsed: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { env.isUnscheduledCollapsed = false }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                Text("UNSCHEDULED")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(height: 96)
                Text("\(env.unscheduled.count)").font(.system(size: 10.5))
                Spacer()
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, 12)
            .frame(width: Metrics.collapsedWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: Metrics.columnCorner, style: .continuous)
                    .fill(Palette.column)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.columnCorner, style: .continuous)
                    .strokeBorder(isTargeted ? Palette.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .help("Show unscheduled tasks")
    }
}

/// Work that slipped past the current week entirely.
///
/// Deliberately *not* everything overdue: something due Monday when today is Tuesday
/// stays on Monday, where the week in progress can still absorb it. Only once the whole
/// week has rolled past does it land here.
struct BacklogColumn: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false

    var body: some View {
        @Bindable var env = env
        return BoardColumn(
            tint: env.backlog.isEmpty ? Palette.column : Palette.overdue.opacity(0.07),
            isTargeted: isTargeted
        ) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                Text("BACKLOG")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                Spacer()
                AgeSortMenu(sort: $env.backlogSort, help: "Sort backlog")
                if !env.backlog.isEmpty {
                    Text("\(env.backlog.count)").font(.system(size: 10.5))
                }
            }
            .foregroundStyle(env.backlog.isEmpty ? Palette.textSecondary : Palette.overdue)
        } content: {
            ForEach(env.backlog) { task in
                TaskCardView(task: task).draggable(task.id)
            }
            if env.backlog.isEmpty {
                EmptyHint(text: "Nothing overdue")
            }
        } footer: {
            EmptyView()
        }
        .dropDestination(for: String.self) { ids, _ in
            // Nothing sensible to write, for a card or for the +: backlog membership is
            // derived from dates already past, not a state you can assign, so there is no
            // such thing as a new task that belongs here. Reject so the drag springs back.
            _ = ids
            return false
        } isTargeted: { isTargeted = $0 }
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }
}

/// The one field a new task is typed into.
///
/// Every column used to carry its own, permanently visible — nine text fields on the week
/// board, each one a click target competing with the cards above it. Now there is a single
/// field that appears in whichever column the + was clicked from or dropped onto, and
/// `AppEnvironment.composeTarget` guarantees there is never a second.
///
/// It stays open after a submit. Tasks arrive in runs, and Reminders keeps its own new row
/// alive the same way.
struct ComposeField: View {
    let target: ComposeTarget
    var placeholder = "New task  ·  !! #list tomorrow"

    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isFocused)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.75), lineWidth: 1.5)
            )
            .onAppear { isFocused = true }
            .onSubmit(submit)
            // Escape abandons it, as it does in every other Mac text field.
            .onExitCommand { env.endCompose(target) }
            .onChange(of: isFocused) { _, focused in
                // Clicking away from an empty field closes it. A field left behind in a
                // column with nothing in it reads as a rendering fault, not an invitation.
                if !focused, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    env.endCompose(target)
                }
            }
            .help("""
                Type a task. Optional shorthand:
                  !  !!  !!!      low / medium / high priority
                  #list           file it in a list, e.g. #freelance
                  tomorrow, friday, next week, in 3 days
                A date word only counts at the start or end, so "Prep Tuesday's \
                invoice" keeps its title.
                Escape closes the field.
                """)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            env.endCompose(target)
            return
        }
        text = ""
        env.commitCompose(trimmed, in: target)
        isFocused = true
    }
}


/// Chooses which lists feed the Unscheduled column.
///
/// Deliberately its own filter rather than reusing the board's: an archival list can be
/// kept out of the planning pool while its dated tasks still show up on their days.
struct UnscheduledFilterMenu: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Menu {
            Button("Include All Lists") { env.unscheduledListIDs.removeAll() }
            Divider()
            ForEach(env.store.lists) { list in
                Toggle(list.title, isOn: binding(for: list))
            }
        } label: {
            Image(systemName: env.unscheduledListIDs.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(env.unscheduledListIDs.isEmpty ? Palette.textSecondary : Palette.accent)
        .help("Choose which lists appear in Unscheduled")
    }

    private func binding(for list: TaskList) -> Binding<Bool> {
        Binding(
            get: { env.unscheduledListIDs.isEmpty || env.unscheduledListIDs.contains(list.id) },
            set: { isOn in
                // Empty means "every list". The first untick has to seed the set from all
                // of them, or it would hide everything except the one just unticked.
                if env.unscheduledListIDs.isEmpty {
                    env.unscheduledListIDs = Set(env.store.lists.map(\.id))
                }
                if isOn { env.unscheduledListIDs.insert(list.id) }
                else { env.unscheduledListIDs.remove(list.id) }
                if env.unscheduledListIDs.count == env.store.lists.count {
                    env.unscheduledListIDs.removeAll()
                }
            }
        )
    }
}


/// Chooses how a past-due pile is ordered.
///
/// Takes a binding rather than reaching for one shared preference. The Week board's
/// Backlog and the Today board's Overdue column look alike but hold different sets — one
/// is "slipped past the whole week", the other "its day has gone" — so they get their own
/// orderings. A single control governing both would be one control governing two
/// different questions.
struct AgeSortMenu: View {
    @Binding var sort: BacklogSort
    let help: String

    var body: some View {
        Menu {
            ForEach(BacklogSort.allCases, id: \.self) { option in
                Button {
                    sort = option
                } label: {
                    // A leading checkmark marks the active option, matching how the
                    // other menus in the app read.
                    Label(option.label, systemImage: sort == option ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: sort.symbol)
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(help): \(sort.label)")
    }
}
