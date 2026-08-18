import RemindersCore
import SwiftUI

/// Drag payloads. A card can be dragged two ways, so the payload carries which.
enum DragPayload {
    static let spanPrefix = "span:"

    static func encodeSpan(_ id: String) -> String { spanPrefix + id }

    /// Returns the task id and whether this was a span-handle drag.
    static func decode(_ value: String) -> (id: String, isSpan: Bool) {
        value.hasPrefix(spanPrefix)
            ? (String(value.dropFirst(spanPrefix.count)), true)
            : (value, false)
    }
}

struct TaskCardView: View {
    let task: TaskItem
    var isContinuation = false
    /// Day columns show a grab handle for dragging the far end of a span across dates.
    /// Undated columns do not — there is no span to stretch.
    var showsSpanHandle = false
    /// Called when another card is dropped onto this one, to insert it directly above.
    var onDropAbove: ((String) -> Bool)?
    /// Called when a span handle is dropped onto this card. Cards cover the column's own
    /// drop area, and a rejected inner drop is not forwarded to the ancestor, so without
    /// this a span released over a card would silently do nothing.
    var onSpanDrop: ((String) -> Bool)?

    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false
    @State private var isReorderTarget = false
    @State private var showsDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Checkbox(isOn: task.isCompleted, tint: Color(task.listColor)) {
                Task { await env.store.setCompleted(task, !task.isCompleted) }
            }
            .padding(.top, 1)
            .opacity(isContinuation ? 0 : 1)
            .disabled(isContinuation)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isContinuation ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(3)
                    .strikethrough(task.isCompleted, color: Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(task.listColor))
                            .frame(width: 5, height: 5)
                        Text(task.listName)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }

                    if task.priority != .none {
                        Text(priorityGlyph)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(priorityColor)
                    }
                    // The distinction the start/due split exists for: planned for one
                    // day, actually owed on another.
                    if let due = task.dueDay, task.spansMultipleDays {
                        HStack(spacing: 2.5) {
                            Image(systemName: "flag.fill").font(.system(size: 8))
                            Text(due.monthDayLabel).font(.system(size: 10.5))
                        }
                        .foregroundStyle(task.isOverdue() ? Palette.overdue : Palette.flag)
                    }
                    if let time = task.dueTimeLabel {
                        Text(time)
                            .font(.system(size: 10.5))
                            .foregroundStyle(task.isOverdue() ? Palette.overdue : Palette.textSecondary)
                    }
                    if task.hasNotes {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.textTertiary)
                            .help("Has notes")
                    }
                    if task.hasAlarms {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.textTertiary)
                            .help("Has a Reminders notification — rescheduling never changes it")
                    }
                    if task.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    if let minutes = task.estimateMinutes {
                        Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            // A hairline rather than a drop shadow — Things separates with edges and
            // whitespace, never with elevation.
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(
                    task.isOverdue() ? Palette.overdue.opacity(0.5)
                        : (isHovering ? Palette.accent.opacity(0.45) : Palette.cardBorder),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .top) {
            // A line above the card marks where a dropped card will land.
            if isReorderTarget {
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: 2.5)
                    .offset(y: -4)
            }
        }
        .overlay(alignment: .topTrailing) { detailButton }
        .overlay(alignment: .trailing) { spanHandle }
        .popover(isPresented: $showsDetail, arrowEdge: .trailing) {
            TaskDetailView(task: task).environment(env)
        }
        .opacity(isContinuation ? 0.5 : 1)
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            let (id, isSpan) = DragPayload.decode(raw)
            if isSpan { return onSpanDrop?(id) ?? false }
            guard let onDropAbove, id != task.id else { return false }
            return onDropAbove(id)
        } isTargeted: { isReorderTarget = $0 && onDropAbove != nil }
    }

    @ViewBuilder private var detailButton: some View {
        if isHovering, !isContinuation {
            Button { showsDetail = true } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 12))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Palette.textSecondary, Palette.card)
            }
            .buttonStyle(.plain)
            .padding(5)
            .help("Show details")
        }
    }

    @ViewBuilder private var spanHandle: some View {
        if showsSpanHandle, !isContinuation, isHovering {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.accent.opacity(0.75))
                .frame(width: 4)
                .padding(.vertical, 6)
                .padding(.trailing, 2)
                .draggable(DragPayload.encodeSpan(task.id))
                .help("Drag across days to make this a multi-day task")
        }
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

    @ViewBuilder private var menu: some View {
        Button("Show Details…") { showsDetail = true }
        Divider()
        Menu("Priority") {
            ForEach(Priority.allCases, id: \.self) { p in
                Button(p.label) { Task { await env.store.setPriority(task, p) } }
            }
        }
        Menu("Estimate") {
            Button("Clear") { env.store.setEstimate(nil, for: task) }
            ForEach([15, 30, 60, 120, 240], id: \.self) { m in
                Button(m >= 60 ? "\(m / 60)h" : "\(m)m") { env.store.setEstimate(m, for: task) }
            }
        }
        Menu("Move to List") {
            ForEach(env.store.lists.filter(\.isEditable)) { list in
                Button(list.title) { Task { await env.store.move(task, toList: list.id) } }
            }
        }
        Divider()
        Button("Plan for Today") { Task { await env.store.schedule(task, to: .today()) } }
        Button("Remove Planned Day") { Task { await env.store.schedule(task, to: nil) } }
        if task.dueDay != nil {
            Button("Clear Deadline") { Task { await env.store.clearSpanEnd(task) } }
        }
        Divider()
        Button("Delete", role: .destructive) { Task { await env.store.delete(task) } }
    }
}
