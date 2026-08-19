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
    @State private var hasAlarm = false
    @State private var alarmDate = Date()
    @State private var repeats = false
    @State private var frequency: RecurrenceFrequency = .weekly
    @State private var interval = 1
    /// Set when an edit would replace something Reminders is already managing.
    @State private var pendingOverride: Override?

    /// Changing a notification or a repeat rule is the one place this app writes over
    /// something the user set up in Reminders, so it asks first — and only when something
    /// is actually being replaced, never when adding to a task that had none.
    enum Override: Identifiable {
        case alarm(Date?)
        case recurrence(SimpleRecurrence?)
        var id: String {
            switch self {
            case .alarm: "alarm"; case .recurrence: "recurrence"
            }
        }
    }

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
                    alertAndRepeat
                    separator
                    menus
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
        .confirmationDialog(
            "Override Reminders?",
            isPresented: Binding(
                get: { pendingOverride != nil },
                set: { if !$0 { revertPending() } }
            ),
            presenting: pendingOverride
        ) { override in
            Button("Change it") { apply(override) }
            Button("Cancel", role: .cancel) { revertPending() }
        } message: { override in
            switch override {
            case .alarm:
                Text("This reminder's notification was set in Reminders. Changing it here replaces it, and the old alert won't fire.")
            case .recurrence:
                Text("This reminder's repeat rule was set in Reminders. Changing it here replaces it.")
            }
        }
    }

    /// Applies immediately when nothing is being replaced; asks first when something is.
    private func request(_ override: Override, replacing existing: Bool) {
        if existing {
            pendingOverride = override
        } else {
            apply(override)
        }
    }

    private func requestRepeat() {
        let rule = repeats
            ? SimpleRecurrence(frequency: frequency, interval: interval)
            : nil
        request(.recurrence(rule), replacing: task.isRecurring)
    }

    private func apply(_ override: Override) {
        pendingOverride = nil
        Task {
            switch override {
            case let .alarm(date): await env.store.setAlarm(task, at: date)
            case let .recurrence(rule): await env.store.setRecurrence(task, rule)
            }
        }
    }

    /// Puts the toggles back where the reminder actually is, so a cancelled dialog does
    /// not leave the UI claiming a change that never happened.
    private func revertPending() {
        pendingOverride = nil
        hasAlarm = task.hasAlarms
        repeats = task.isRecurring
        if let shape = task.recurrence?.simple {
            frequency = shape.frequency
            interval = shape.interval
        }
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

    /// Reminders' own "Remind me" and "Repeat" rows.
    private var alertAndRepeat: some View {
        VStack(spacing: 0) {
            let lockedAlarm = task.alarms.first { !$0.isEditableHere }
            let lockedRepeat = task.recurrence.map { !$0.isEditableHere } ?? false

            if let lockedAlarm {
                // A geofence cannot be rebuilt here, so it is shown rather than offered up
                // to an editor that would replace it with something lesser.
                lockedRow("Notification", detail: lockedAlarm.label)
            } else {
                row("Notification") {
                    HStack(spacing: 6) {
                        if hasAlarm {
                            DatePicker("", selection: $alarmDate)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .onChange(of: alarmDate) { _, new in
                                    request(.alarm(new), replacing: task.hasAlarms)
                                }
                        }
                        Toggle("", isOn: $hasAlarm)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: hasAlarm) { _, on in
                                request(.alarm(on ? alarmDate : nil), replacing: task.hasAlarms)
                            }
                    }
                }
            }

            if lockedRepeat, let shape = task.recurrence {
                lockedRow("Repeat", detail: shape.label)
            } else if !hasDue {
                // A repeat is anchored to the deadline; EventKit drops a rule written
                // without one. Reminders hides the control in the same situation.
                row("Repeat") {
                    Text("Needs a deadline")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
            } else {
                row("Repeat") {
                    HStack(spacing: 6) {
                        if repeats {
                            Picker("", selection: $frequency) {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: frequency) { _, _ in requestRepeat() }

                            Stepper("\(interval)", value: $interval, in: 1...30)
                                .font(.system(size: 11.5))
                                .fixedSize()
                                .onChange(of: interval) { _, _ in requestRepeat() }
                        }
                        Toggle("", isOn: $repeats)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: repeats) { _, _ in requestRepeat() }
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

    /// A row this app deliberately will not edit, with the reason attached.
    private func lockedRow(_ label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 12.5)).foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
            Text("More detailed than this app can edit — change it in Reminders.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
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

        hasAlarm = task.hasAlarms
        if case let .absolute(date)? = task.alarms.first { alarmDate = date }
        repeats = task.isRecurring
        if let shape = task.recurrence?.simple {
            frequency = shape.frequency
            interval = shape.interval
        }
    }

    private func applyDueTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        Task { await env.store.setDueTime(task, hour: parts.hour, minute: parts.minute) }
    }

    /// Text commits on Done rather than per keystroke — every write round-trips to EventKit
    /// and refetches, which would be unusable while typing.
    ///
    /// All three fields go in one call: as three separate `Task`s this was three commits and
    /// three full refetches per click, in no guaranteed order.
    private func commitAll() {
        let newTitle = title != task.title ? title : nil
        let newNotes = notes != (task.notes ?? "") ? notes : nil
        let newURL = urlText != (task.url?.absoluteString ?? "") ? urlText : nil
        guard newTitle != nil || newNotes != nil || newURL != nil else { return }
        Task { await env.store.setFields(task, title: newTitle, notes: newNotes, url: newURL) }
    }

    /// The title field also commits on Enter, which is the one field worth writing early —
    /// it is the task's identity and the most likely thing to be retyped.
    private func commitTitle() {
        guard title != task.title else { return }
        Task { await env.store.setTitle(task, title) }
    }

    private func commitURL() {
        guard urlText != (task.url?.absoluteString ?? "") else { return }
        Task { await env.store.setURL(task, urlText) }
    }
}
