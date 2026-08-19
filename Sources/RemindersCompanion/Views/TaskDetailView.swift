import RemindersCore
import SwiftUI

/// Everything Reminders holds for a task, laid out the way Reminders itself lays it out.
///
/// The structure deliberately mirrors the Reminders info popover — free-text fields at the
/// top, then date rows, then the menus — so nobody has to learn a second arrangement of
/// the same information. Labels sit on the left, controls on the right, groups separated by
/// hairlines rather than boxes.
///
/// Two absences are deliberate:
///
/// - **Location.** `EKCalendarItem.location` exists and EventKit accepts a value, but
///   iCloud silently discards it for reminders (verified: written directly to a live
///   `EKReminder`, saved, and gone on refetch). It works for calendar *events*, which share
///   the superclass. A field that quietly eats what you type is worse than no field.
/// - **Flags, tags, subtasks.** Absent from EventKit entirely; no third-party app can
///   reach them.
struct TaskDetailView: View {
    let task: TaskItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var urlText = ""
    @State private var hasPlanned = false
    @State private var plannedDate = Date()
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    freeText
                    separator
                    dateRows
                    separator
                    menus
                    if task.hasAlarms || task.isRecurring {
                        separator
                        fromReminders
                    }
                }
                .padding(.vertical, 4)
            }

            Divider().overlay(Palette.separator)
            footer
        }
        .frame(width: 340)
        .frame(maxHeight: 580)
        .background(Palette.window)
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Checkbox(isOn: task.isCompleted, tint: Color(task.listColor)) {
                Task {
                    await env.store.setCompleted(task, !task.isCompleted)
                    dismiss()
                }
            }
            Text(task.isCompleted ? "Completed" : "Details")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Plain fields with placeholders, as Reminders has them — no boxes, no captions.
    private var freeText: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1...3)
                .onSubmit { commitTitle() }

            TextField("Notes", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...6)
                .foregroundStyle(Palette.textPrimary)

            TextField("URL", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit { commitURL() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var dateRows: some View {
        VStack(spacing: 0) {
            // "Plan for" is this app's own idea — Reminders has no do-date — so it is
            // named distinctly rather than dressed up as something Reminders shows.
            row("Plan for") {
                HStack(spacing: 6) {
                    if hasPlanned {
                        DatePicker("", selection: $plannedDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: plannedDate) { _, new in
                                Task { await env.store.schedule(task, to: Day(new)) }
                            }
                    }
                    Toggle("", isOn: $hasPlanned)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: hasPlanned) { _, on in
                            Task { await env.store.schedule(task, to: on ? Day(plannedDate) : nil) }
                        }
                }
            }

            row("Deadline") {
                HStack(spacing: 6) {
                    if hasDue {
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: dueDate) { _, new in
                                Task { await env.store.setDueDay(task, to: Day(new)) }
                            }
                    }
                    Toggle("", isOn: $hasDue)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: hasDue) { _, on in
                            Task { await env.store.setDueDay(task, to: on ? Day(dueDate) : nil) }
                            if !on { hasDueTime = false }
                        }
                }
            }

            if hasDue {
                row("At a time", indented: true) {
                    HStack(spacing: 6) {
                        if hasDueTime {
                            DatePicker("", selection: $dueTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .onChange(of: dueTime) { _, new in applyDueTime(new) }
                        }
                        Toggle("", isOn: $hasDueTime)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: hasDueTime) { _, on in
                                if on {
                                    applyDueTime(dueTime)
                                } else {
                                    Task { await env.store.setDueTime(task, hour: nil, minute: nil) }
                                }
                            }
                    }
                }
            }
        }
    }

    private var menus: some View {
        VStack(spacing: 0) {
            row("Priority") {
                Picker("", selection: Binding(
                    get: { task.priority },
                    set: { p in Task { await env.store.setPriority(task, p) } }
                )) {
                    ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            row("List") {
                Picker("", selection: Binding(
                    get: { task.listID },
                    set: { id in Task { await env.store.move(task, toList: id) } }
                )) {
                    ForEach(env.store.lists.filter(\.isEditable)) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            row("Estimate") {
                Picker("", selection: Binding(
                    get: { task.estimateMinutes ?? 0 },
                    set: { m in env.store.setEstimate(m == 0 ? nil : m, for: task) }
                )) {
                    Text("None").tag(0)
                    ForEach([15, 30, 45, 60, 120, 240, 480], id: \.self) { m in
                        Text(m >= 60 ? "\(m / 60)h" : "\(m)m").tag(m)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// Shown, not editable — deliberately, for now. These are the two things the user
    /// trusts Reminders for, and an editor for either gets its own verified pass.
    private var fromReminders: some View {
        VStack(alignment: .leading, spacing: 6) {
            if task.hasAlarms {
                fact("bell.fill", "Has a notification — set it in Reminders")
            }
            if task.isRecurring {
                fact("repeat", "Repeats — completing it rolls the series forward")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            Button("Delete", role: .destructive) {
                Task {
                    await env.store.delete(task)
                    dismiss()
                }
            }
            .buttonStyle(.link)
            .tint(Palette.overdue)
            Spacer()
            Button("Done") {
                commitAll()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .keyboardShortcut(.defaultAction)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    /// A Reminders-style row: label left, control right, on one baseline.
    private func row<Content: View>(
        _ label: String, indented: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(indented ? Palette.textSecondary : Palette.textPrimary)
            Spacer(minLength: 8)
            content()
        }
        .padding(.leading, indented ? 28 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
    }

    private var separator: some View {
        Divider().overlay(Palette.separator).padding(.vertical, 2)
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(text).font(.system(size: 11.5))
        }
        .foregroundStyle(Palette.textSecondary)
    }

    // MARK: - Loading and committing

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        title = task.title
        notes = task.notes ?? ""
        urlText = task.url?.absoluteString ?? ""
        hasPlanned = task.plannedDay != nil
        plannedDate = (task.plannedDay ?? .today()).startOfDay()
        hasDue = task.dueDay != nil
        dueDate = (task.dueDay ?? .today()).startOfDay()
        hasDueTime = task.dueIsTimed
        dueTime = task.dueDate
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
            ?? Date()
    }

    private func applyDueTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        Task { await env.store.setDueTime(task, hour: parts.hour, minute: parts.minute) }
    }

    /// Text commits on Done rather than per keystroke — every write round-trips to EventKit
    /// and refetches, which would be unusable while typing.
    private func commitAll() {
        commitTitle()
        commitNotes()
        commitURL()
    }

    private func commitTitle() {
        guard title != task.title else { return }
        Task { await env.store.setTitle(task, title) }
    }

    private func commitNotes() {
        guard notes != (task.notes ?? "") else { return }
        Task { await env.store.setNotes(task, notes) }
    }

    private func commitURL() {
        guard urlText != (task.url?.absoluteString ?? "") else { return }
        Task { await env.store.setURL(task, urlText) }
    }
}
