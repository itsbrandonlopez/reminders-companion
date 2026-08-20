import RemindersCore
import SwiftUI

/// One Reminders list, shown the way Reminders shows it: everything in the list, flat, in
/// order, dated or not.
///
/// Clicking a list used to drill the *week board* into it. That answered "what of this
/// list is planned this week", which is a narrower question than the one a list row asks —
/// and it quietly hid every undated task, which for most lists is most of them. The boards
/// are for planning across lists; a list is for seeing what is in it.
///
/// Completed tasks are absent because the store fetches only incomplete reminders — the
/// same reason the boards never show them. Reminders hides them behind a menu by default
/// too, so the default view matches; there is simply no way to ask for them back yet.
///
/// Give the list sections and it becomes a board of columns instead, which is how
/// Reminders renders the same list. Presence of sections is the whole switch: no extra
/// toggle to set, and no way for the toggle and the content to disagree.
struct ListDetailView: View {
    let listID: String

    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false
    @State private var isCreatingSection = false
    @State private var newSectionName = ""
    @State private var renaming: ListSection?
    @State private var renameText = ""

    private var sections: [ListSection] { env.sections(in: listID) }

    /// The list this view is about. Nil for the moment between deleting a list in
    /// Reminders and the refresh that notices.
    private var list: TaskList? {
        env.store.lists.first { $0.id == listID }
    }

    /// `focus` is already `.list(id)`, so the shared slice is exactly this list's tasks,
    /// in manual order and narrowed by the search field. Deriving it a second time here
    /// would be a second definition of the same thing.
    private var tasks: [TaskItem] { env.filteredTasks }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.separator)
            if !sections.isEmpty {
                ListSectionBoardView(
                    listID: listID,
                    sections: sections,
                    tasks: tasks,
                    onRename: { section in
                        renameText = section.name
                        renaming = section
                    },
                    onAddSection: beginCreatingSection
                )
            } else if tasks.isEmpty && env.composeTarget != .list(listID) {
                empty
            } else {
                rows
            }
        }
        .background(Palette.window)
        // Only the flat list takes a bare drop: the board's own columns each answer for
        // themselves, and a drop that missed all of them has no section to mean.
        .dropDestination(for: String.self) { ids, _ in
            guard sections.isEmpty,
                  let raw = ids.first,
                  case .newTask = DragPayload.kind(raw) else { return false }
            return compose()
        } isTargeted: { isTargeted = $0 && sections.isEmpty }
        .overlay(
            Rectangle()
                .strokeBorder(isTargeted ? Palette.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        )
        .alert("New Section", isPresented: $isCreatingSection) {
            TextField("Name", text: $newSectionName)
            Button("Cancel", role: .cancel) { newSectionName = "" }
            Button("Create") {
                env.createSection(named: newSectionName, in: listID)
                newSectionName = ""
            }
        } message: {
            Text("Sections live in this app only — Reminders exposes none of its own to any app, so give this the same name you used there and they will line up.")
        }
        .alert("Rename Section", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let section = renaming { env.rename(section, to: renameText) }
                renaming = nil
            }
        }
    }

    private func beginCreatingSection() {
        newSectionName = ""
        isCreatingSection = true
    }

    private var tint: Color { list.map { Color($0.color) } ?? Palette.accent }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(list?.title ?? "List")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text("\(tasks.count)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
            Spacer()
            Menu {
                Button("Add Section…", action: beginCreatingSection)
                if !sections.isEmpty {
                    Divider()
                    Menu("Rename Section") {
                        ForEach(sections) { section in
                            Button(section.name) {
                                renameText = section.name
                                renaming = section
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Palette.textSecondary)
            .help(sections.isEmpty
                  ? "Add a section — the list becomes a board of columns"
                  : "Manage this list's sections")

            if list?.isEditable == false {
                Text("Read-only")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .help("Reminders does not allow this list to be edited")
            }
            if env.store.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 11)
        .background(Palette.window)
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    ListTaskRow(
                        task: task,
                        tint: tint,
                        onDropAbove: { droppedID in insert(droppedID, above: index) },
                        onNewTaskDrop: { compose() }
                    )
                    .draggable(task.id)
                    Divider()
                        .overlay(Palette.separator)
                        .padding(.leading, 44)
                }

                if env.composeTarget == .list(listID) {
                    ComposeField(
                        target: .list(listID),
                        placeholder: "New task  ·  !! tomorrow"
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                }
            }
            // Clears the floating + so the last row is never stuck underneath it.
            .padding(.bottom, 76)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Nothing in this list")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            Text(env.searchText.isEmpty
                 ? "Use the + to add something, or drag it here."
                 : "No task in this list matches “\(env.searchText)”.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }

    private func compose() -> Bool {
        guard list?.isEditable != false else { return false }
        env.beginCompose(.list(listID))
        return true
    }

    /// Manual reordering, the same fractional-rank write the board columns do. The
    /// neighbourhood is this list rather than a day, which is the ordering Reminders
    /// itself shows.
    private func insert(_ droppedID: String, above index: Int) -> Bool {
        // Re-read rather than trusting the captured index: a background refresh between
        // render and drop can shrink the array out from under it.
        let column = tasks
        guard index < column.count,
              let dragged = env.store.tasks.first(where: { $0.id == droppedID }),
              dragged.listID == listID else { return false }
        env.store.reorder(
            dragged,
            above: index > 0 ? column[index - 1] : nil,
            below: column[index],
            within: column
        )
        return true
    }
}

/// One task as a row rather than a card.
///
/// A card carries its list's name and colour because a board column mixes lists; inside a
/// list every row would repeat the same two, so they come out and the dates move up into
/// the space. Everything else — the checkbox, the detail popover, the right-click menu —
/// is the same object the cards use.
struct ListTaskRow: View {
    let task: TaskItem
    let tint: Color
    var onDropAbove: ((String) -> Bool)?
    var onNewTaskDrop: (() -> Bool)?

    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false
    @State private var isReorderTarget = false
    @State private var showsDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Checkbox(isOn: task.isCompleted, tint: tint) {
                Task { await env.store.setCompleted(task, !task.isCompleted) }
            }
            .padding(.top, 1.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(task.isCompleted, color: Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let notes = task.notes, task.hasNotes {
                    Text(notes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }

                dates
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                if task.priority != .none {
                    Text(priorityGlyph)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(priorityColor)
                }
                if task.hasAlarms {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                        .help("Has a Reminders notification — rescheduling never changes it")
                }
                if task.isRecurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                }
                if let minutes = task.estimateMinutes {
                    Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(isHovering ? Palette.column : Color.clear)
        .overlay(alignment: .top) {
            if isReorderTarget {
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: 2.5)
                    .padding(.leading, 44)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showsDetail = true }
        .onHover { isHovering = $0 }
        .popover(isPresented: $showsDetail, arrowEdge: .trailing) {
            TaskDetailView(task: task).environment(env)
        }
        .contextMenu { TaskMenu(task: task, showsDetail: $showsDetail) }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            switch DragPayload.kind(raw) {
            case .newTask:
                return onNewTaskDrop?() ?? false
            case .span:
                // Spans are stretched across day columns. A list has no days to stretch to.
                return false
            case let .task(id):
                guard let onDropAbove, id != task.id else { return false }
                return onDropAbove(id)
            }
        } isTargeted: { isReorderTarget = $0 && onDropAbove != nil }
    }

    /// The two dates, kept apart on purpose: the deadline is what the task owes, the
    /// planned day is when you intend to do it. A row shows the planned day only when it
    /// differs, since saying the same date twice reads as a bug.
    @ViewBuilder private var dates: some View {
        let planned = task.plannedDay
        let due = task.dueDay
        if planned != nil || due != nil {
            HStack(spacing: 9) {
                if let due {
                    HStack(spacing: 3.5) {
                        Image(systemName: "flag.fill").font(.system(size: 8.5))
                        Text(label(for: due) + (task.dueTimeLabel.map { ", \($0)" } ?? ""))
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(task.isOverdue() ? Palette.overdue : Palette.flag)
                    .help("Deadline")
                }
                if let planned, planned != due {
                    HStack(spacing: 3.5) {
                        Image(systemName: "calendar").font(.system(size: 8.5))
                        Text(label(for: planned))
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(planned.isPast ? Palette.overdue : Palette.accent)
                    .help("Planned day")
                }
            }
        }
    }

    /// Names the days worth naming, a weekday for the coming week, and a date after that —
    /// "Monday" three months out would read as this Monday.
    private func label(for day: Day) -> String {
        let today = Day.today()
        if day == today || day == today.adding(days: 1) || day == today.adding(days: -1) {
            return day.relativeName
        }
        if day > today, day < today.adding(days: 7) { return day.fullWeekday }
        return day.monthDayLabel
    }

    private var priorityGlyph: String {
        switch task.priority {
        case .high: "!!!"; case .medium: "!!"; case .low: "!"; case .none: ""
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: Palette.overdue; case .medium: Palette.flag
        case .low: Palette.textSecondary; case .none: Palette.textTertiary
        }
    }
}
