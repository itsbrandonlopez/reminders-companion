import RemindersCore
import SwiftUI

/// One task, flat. Deliberately not grouped by list — the colour dot carries provenance
/// so the week reads as a sequence of days rather than a grid of projects.
struct TaskRow: View {
    let task: TaskItem
    /// Quick-schedule actions vary by context; Triage needs them, the week does not.
    var showsScheduleActions = false

    @Environment(MobileEnvironment.self) private var env
    @State private var showsSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                Task { await env.store.setCompleted(task, true) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Color(task.listColor))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 7) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(task.listColor)).frame(width: 6, height: 6)
                        Text(task.listName)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if task.priority != .none {
                        Text(priorityGlyph)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(priorityColor)
                    }
                    if let time = task.dueTimeLabel {
                        Text(time)
                            .font(.system(size: 12))
                            .foregroundStyle(task.isOverdue() ? Palette.overdue : Palette.textSecondary)
                    }
                    if task.spansMultipleDays, let due = task.dueDay {
                        Label(due.monthDayLabel, systemImage: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(task.isOverdue() ? Palette.overdue : Palette.flag)
                    }
                    if task.hasNotes {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    if task.hasAlarms {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    if task.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(Palette.surface)
        .contentShape(Rectangle())
        .onTapGesture { showsSheet = true }
        .sheet(isPresented: $showsSheet) {
            TaskSheet(task: task).environment(env)
        }
        // Long-press to drag: the gesture the week view is built around.
        .draggable(task.id)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await env.store.setCompleted(task, true) }
            } label: { Label("Done", systemImage: "checkmark") }
                .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            if showsScheduleActions {
                Button {
                    Task { await env.store.schedule(task, to: .today()) }
                } label: { Label("Today", systemImage: "sun.max") }
                    .tint(Palette.accent)
                Button {
                    Task { await env.store.schedule(task, to: Day.today().adding(days: 1)) }
                } label: { Label("Tomorrow", systemImage: "arrow.right") }
                    .tint(Palette.flag)
            } else {
                Button {
                    Task { await env.store.schedule(task, to: nil) }
                } label: { Label("Unschedule", systemImage: "tray") }
                    .tint(Palette.textSecondary)
            }
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
}
