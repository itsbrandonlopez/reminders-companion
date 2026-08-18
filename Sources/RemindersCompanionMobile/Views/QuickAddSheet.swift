import RemindersCore
import SwiftUI

/// Creating a task on the phone.
///
/// Presented as a sheet rather than an inline field because on iOS the keyboard covers
/// roughly half the screen — an inline field at the bottom of a list ends up hidden behind
/// it, which is exactly where a week view would want to put it.
///
/// The live interpretation line underneath the field is the important part: shorthand you
/// can't see the effect of is shorthand you stop trusting. It shows what will actually
/// happen *before* the task is created, so a mis-parse is visible rather than discovered
/// later.
struct QuickAddSheet: View {
    /// What the presenting view implies when the text contains no explicit date.
    let defaultDay: Day?

    @Environment(MobileEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text = ""

    private var parsed: QuickAddParse { QuickAddParser.parse(text) }

    private var resolvedList: TaskList? {
        let editable = env.store.lists.filter(\.isEditable)
        return parsed.listToken.flatMap { QuickAddParser.matchList($0, in: editable) }
            ?? editable.first(where: \.isDefault)
            ?? editable.first
    }

    private var resolvedDay: Day? { parsed.day ?? defaultDay }

    private var canSave: Bool {
        !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Add task", text: $text, axis: .vertical)
                        .focused($isFocused)
                        .lineLimit(1...4)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("Optional shorthand: **!!** priority · **#list** · **tomorrow**, **friday**, **next week**, **in 3 days**")
                }

                if !text.isEmpty {
                    Section("Will create") {
                        LabeledContent("Title") {
                            Text(canSave ? parsed.title : "—")
                                .foregroundStyle(canSave ? Palette.textPrimary : Palette.overdue)
                        }
                        if let list = resolvedList {
                            LabeledContent("List") {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(list.color)).frame(width: 8, height: 8)
                                    Text(list.title)
                                }
                            }
                        }
                        LabeledContent("When", value: resolvedDay?.relativeName ?? "No date")
                        if let priority = parsed.priority {
                            LabeledContent("Priority", value: priority.label)
                        }
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save).disabled(!canSave)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard canSave else { return }
        let input = text
        dismiss()
        Task { await env.quickAdd(input, defaultDay: defaultDay) }
    }
}
