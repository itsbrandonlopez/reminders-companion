import RemindersCore
import SwiftUI

/// The task's full contents, editable. Same store methods as the Mac's detail panel.
///
/// Alarms and recurrence stay read-only for the same reason as on the Mac: editing them
/// well means reproducing Reminders' own notification rules, and those are exactly what
/// the app promises never to disturb.
struct TaskSheet: View {
    let task: TaskItem
    @Environment(MobileEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var hasPlanned = false
    @State private var plannedDate = Date()
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Dates") {
                    Toggle("Planned day", isOn: $hasPlanned)
                        .onChange(of: hasPlanned) { _, on in
                            Task { await env.store.schedule(task, to: on ? Day(plannedDate) : nil) }
                        }
                    if hasPlanned {
                        DatePicker("Plan for", selection: $plannedDate, displayedComponents: .date)
                            .onChange(of: plannedDate) { _, new in
                                Task { await env.store.schedule(task, to: Day(new)) }
                            }
                    }

                    Toggle("Deadline", isOn: $hasDue)
                        .onChange(of: hasDue) { _, on in
                            Task { await env.store.setDueDay(task, to: on ? Day(dueDate) : nil) }
                        }
                    if hasDue {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                            .onChange(of: dueDate) { _, new in
                                Task { await env.store.setDueDay(task, to: Day(new)) }
                            }
                        if let time = task.dueTimeLabel {
                            LabeledContent("Time", value: time)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }

                Section {
                    Picker("Priority", selection: Binding(
                        get: { task.priority },
                        set: { p in Task { await env.store.setPriority(task, p) } }
                    )) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }

                    Picker("List", selection: Binding(
                        get: { task.listID },
                        set: { id in Task { await env.store.move(task, toList: id) } }
                    )) {
                        ForEach(env.store.lists.filter(\.isEditable)) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                }

                if task.hasAlarms || task.isRecurring {
                    Section("From Reminders") {
                        if task.hasAlarms {
                            Label("Has a notification — never changed by this app",
                                  systemImage: "bell.fill")
                        }
                        if task.isRecurring {
                            Label("Repeats — completing it rolls the series forward", systemImage: "repeat")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                }

                Section {
                    Button("Mark Complete") {
                        Task {
                            await env.store.setCompleted(task, true)
                            dismiss()
                        }
                    }
                    Button("Delete", role: .destructive) {
                        Task {
                            await env.store.delete(task)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

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

    /// Text commits on dismiss, not per keystroke — each write round-trips to EventKit
    /// and refetches, which would be unusable while typing.
    private func commit() {
        if title != task.title { Task { await env.store.setTitle(task, title) } }
        if notes != (task.notes ?? "") { Task { await env.store.setNotes(task, notes) } }
    }
}
