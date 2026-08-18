import RemindersCore
import SwiftUI

/// Everything Reminders holds for a task, in one editable panel.
///
/// The board deliberately shows very little per card — a week of dense cards is
/// unreadable — but all of this is already loaded on every refresh. This is where notes,
/// the exact deadline, and the fields with nowhere to live on a card get surfaced.
///
/// Alarms and recurrence are shown read-only on purpose. They are the two things a user
/// most needs to trust, and editing them well means reproducing Reminders' own pickers;
/// showing them plainly and sending people to Reminders to change them is more honest
/// than a half-built editor.
struct TaskDetailView: View {
    let task: TaskItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var hasPlanned = false
    @State private var plannedDate = Date()
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Title") {
                        TextField("Title", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(1...3)
                            .onSubmit { commitTitle() }
                    }

                    field("Notes") {
                        TextEditor(text: $notes)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 64, maxHeight: 120)
                    }

                    dates
                    priorityRow
                    listRow
                    estimateRow

                    if task.hasAlarms || task.isRecurring || task.url != nil {
                        Divider().overlay(Palette.separator)
                        reminderFacts
                    }
                }
                .padding(14)
            }

            Divider().overlay(Palette.separator)
            footer
        }
        .frame(width: 330)
        .frame(maxHeight: 560)
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
            Text(task.isCompleted ? "Completed" : "Task")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $hasPlanned) {
                Text("Planned day").font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .onChange(of: hasPlanned) { _, on in
                Task { await env.store.schedule(task, to: on ? Day(plannedDate) : nil) }
            }

            if hasPlanned {
                DatePicker("", selection: $plannedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: plannedDate) { _, new in
                        Task { await env.store.schedule(task, to: Day(new)) }
                    }
            }

            Toggle(isOn: $hasDue) {
                Text("Deadline").font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .onChange(of: hasDue) { _, on in
                Task { await env.store.setDueDay(task, to: on ? Day(dueDate) : nil) }
            }

            if hasDue {
                HStack(spacing: 8) {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .onChange(of: dueDate) { _, new in
                            Task { await env.store.setDueDay(task, to: Day(new)) }
                        }
                    if let time = task.dueTimeLabel {
                        // The time itself is set in Reminders; changing it here would mean
                        // rebuilding its notification rules.
                        Text(time)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textSecondary)
                            .help("Time of day is set in Reminders")
                    }
                }
            }
        }
    }

    private var priorityRow: some View {
        field("Priority") {
            Picker("", selection: Binding(
                get: { task.priority },
                set: { newPriority in Task { await env.store.setPriority(task, newPriority) } }
            )) {
                ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var listRow: some View {
        field("List") {
            Picker("", selection: Binding(
                get: { task.listID },
                set: { newListID in Task { await env.store.move(task, toList: newListID) } }
            )) {
                ForEach(env.store.lists.filter(\.isEditable)) { list in
                    Text(list.title).tag(list.id)
                }
            }
            .labelsHidden()
        }
    }

    private var estimateRow: some View {
        field("Estimate") {
            Picker("", selection: Binding(
                get: { task.estimateMinutes ?? 0 },
                set: { minutes in env.store.setEstimate(minutes == 0 ? nil : minutes, for: task) }
            )) {
                Text("None").tag(0)
                ForEach([15, 30, 45, 60, 120, 240, 480], id: \.self) { minutes in
                    Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m").tag(minutes)
                }
            }
            .labelsHidden()
        }
    }

    private var reminderFacts: some View {
        VStack(alignment: .leading, spacing: 7) {
            if task.hasAlarms {
                fact("bell.fill", "Has a notification — never changed by this app")
            }
            if task.isRecurring {
                fact("repeat", "Repeats — completing it rolls the series forward")
            }
            if let url = task.url {
                HStack(spacing: 7) {
                    Image(systemName: "link").font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                    Link(url.absoluteString, destination: url)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                }
            }
        }
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
                commitTitle()
                commitNotes()
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

    private func field<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.textTertiary)
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.cardBorder, lineWidth: 1)
                )
        }
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
        hasPlanned = task.plannedDay != nil
        plannedDate = (task.plannedDay ?? .today()).startOfDay()
        hasDue = task.dueDay != nil
        dueDate = (task.dueDay ?? .today()).startOfDay()
    }

    /// Text fields commit on Done rather than per keystroke — every write round-trips to
    /// EventKit and refetches, which would be unusable while typing.
    private func commitTitle() {
        guard title != task.title else { return }
        Task { await env.store.setTitle(task, title) }
    }

    private func commitNotes() {
        guard notes != (task.notes ?? "") else { return }
        Task { await env.store.setNotes(task, notes) }
    }
}
