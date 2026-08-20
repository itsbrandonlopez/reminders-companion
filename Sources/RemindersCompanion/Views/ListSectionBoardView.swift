import RemindersCore
import SwiftUI

/// A sectioned list, as columns — the Kanban view Reminders shows for a list that has
/// sections.
///
/// The sections themselves are typed here rather than read from Reminders, because they
/// cannot be read from Reminders by anyone: see [ListSection] for what was checked. So the
/// names are yours to keep in step, and the arrangement lives on this Mac.
///
/// A list with no sections never reaches this view — it stays a flat list, which is what
/// Reminders shows for the same list. Adding the first section is what turns it into a
/// board, and deleting the last one turns it back.
struct ListSectionBoardView: View {
    let listID: String
    let sections: [ListSection]
    let tasks: [TaskItem]
    /// Raised to the owning view, which holds the rename alert.
    let onRename: (ListSection) -> Void
    let onAddSection: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Metrics.gutter) {
                // Always present, always first. It is where a task lands when it belongs
                // to no section yet, so it has to be a drop target even when empty —
                // dragging a card out of a section needs somewhere to go.
                SectionColumn(
                    listID: listID,
                    section: nil,
                    title: "No Section",
                    tasks: tasks.filter { $0.sectionID == nil },
                    canMoveLeft: false,
                    canMoveRight: false,
                    onRename: {},
                    onDelete: {}
                )

                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    SectionColumn(
                        listID: listID,
                        section: section,
                        title: section.name,
                        tasks: tasks.filter { $0.sectionID == section.id.uuidString },
                        canMoveLeft: index > 0,
                        canMoveRight: index < sections.count - 1,
                        onRename: { onRename(section) },
                        onDelete: { env.delete(section) }
                    )
                }

                addColumn
            }
            .padding(Metrics.gutter)
        }
        .background(Palette.window)
    }

    /// A ghost column at the end, the way every board app offers one. Discoverable in the
    /// place you are already looking when you run out of columns.
    private var addColumn: some View {
        Button(action: onAddSection) {
            VStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add Section")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Palette.textTertiary)
            .frame(width: 148)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: Metrics.columnCorner, style: .continuous)
                    .strokeBorder(
                        Palette.cardBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Sections live in this app only — Reminders does not expose its own")
    }
}

/// One column of a sectioned list.
///
/// Dropping a card here files it into this section, which is a sidecar write and nothing
/// more: the task's list, dates and alarms are untouched, and the same task is exactly
/// where it was if you open Reminders.
private struct SectionColumn: View {
    let listID: String
    /// Nil for the unsectioned column, which cannot be renamed, deleted or moved.
    let section: ListSection?
    let title: String
    let tasks: [TaskItem]
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var isTargeted = false

    private var sectionID: String? { section?.id.uuidString }
    private var target: ComposeTarget { .listSection(list: listID, section: sectionID) }

    var body: some View {
        BoardColumn(
            tint: section == nil ? Palette.column.opacity(0.6) : Palette.column,
            isTargeted: isTargeted
        ) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                }
                if section != nil { menu }
            }
            .foregroundStyle(section == nil ? Palette.textTertiary : Palette.textSecondary)
        } content: {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskCardView(
                    task: task,
                    showsList: false,
                    onDropAbove: { droppedID in insert(droppedID, above: index) },
                    onNewTaskDrop: { compose() }
                )
                .draggable(task.id)
            }
            if tasks.isEmpty {
                EmptyHint(text: section == nil ? "Everything is filed" : "Empty")
            }
        } footer: {
            if env.composeTarget == target {
                ComposeField(target: target, placeholder: "New task  ·  !! tomorrow")
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let raw = ids.first else { return false }
            switch DragPayload.kind(raw) {
            case .newTask:
                return compose()
            case .span:
                // Spans are stretched across days. A section is not a day.
                return false
            case let .task(id):
                return file(id)
            }
        } isTargeted: { isTargeted = $0 }
    }

    @ViewBuilder private var menu: some View {
        Menu {
            Button("Rename…", action: onRename)
            if canMoveLeft { Button("Move Left") { move(-1) } }
            if canMoveRight { Button("Move Right") { move(1) } }
            Divider()
            Button("Delete Section", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Rename, reorder or delete this section")
    }

    private func move(_ offset: Int) {
        guard let section else { return }
        env.move(section, by: offset)
    }

    private func compose() -> Bool {
        env.beginCompose(target)
        return true
    }

    /// Files a dropped task into this column.
    private func file(_ id: String) -> Bool {
        guard let task = env.store.tasks.first(where: { $0.id == id }),
              task.listID == listID,
              task.sectionID != sectionID else { return false }
        env.store.setSection(sectionID, for: task)
        return true
    }

    /// Drops onto a card place the task above it, and file it into this column if it came
    /// from another one — the same gesture answering both questions, as it does on the
    /// week board.
    private func insert(_ droppedID: String, above index: Int) -> Bool {
        let column = tasks
        guard index < column.count,
              let dragged = env.store.tasks.first(where: { $0.id == droppedID }),
              dragged.listID == listID else { return false }
        if dragged.sectionID != sectionID {
            env.store.setSection(sectionID, for: dragged)
        }
        env.store.reorder(
            dragged,
            above: index > 0 ? column[index - 1] : nil,
            below: column[index],
            within: column
        )
        return true
    }
}
