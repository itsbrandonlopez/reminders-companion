import RemindersCore
import SwiftUI

/// Your lists, and inside them the sections you arranged on the Mac.
///
/// New here, and it only earns its place because the sidecar syncs now. Before that, a
/// list on the phone could show its tasks but nothing about how they were organised —
/// which is most of the reason to open a list rather than the Today view.
struct ListsView: View {
    @Environment(MobileEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            Group {
                if env.store.lists.isEmpty {
                    ContentUnavailableView(
                        "No lists",
                        systemImage: "list.bullet",
                        description: Text("Lists come from Reminders. Create one there and it appears here.")
                    )
                } else {
                    List {
                        ForEach(env.store.lists) { list in
                            NavigationLink {
                                MobileListDetailView(list: list).environment(env)
                            } label: {
                                row(for: list)
                            }
                        }

                        if !env.sidecarStorage.isSyncing {
                            Section {
                                Label {
                                    Text("Sections and manual order are arranged on the Mac and reach this phone through iCloud. This build isn't signed for iCloud yet, so lists show flat.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.textSecondary)
                                } icon: {
                                    Image(systemName: "icloud.slash")
                                        .foregroundStyle(Palette.textTertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaPadding(.bottom, 72)   // clears the floating add button
                    .refreshable { await env.store.refresh() }
                }
            }
            .navigationTitle("Lists")
            .background(Palette.background)
        }
    }

    private func row(for list: TaskList) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color(list.color)).frame(width: 27, height: 27)
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(list.title)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 6)
            Text("\(env.tasks(in: list.id).count)")
                .font(.system(size: 14))
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

/// One list on the phone: its tasks, under the section headings they were filed into.
///
/// Headers rather than the Mac's columns. A column is a shape that needs width to be worth
/// anything, and a phone has one column of width — so the same arrangement is rendered the
/// way the platform can actually show it, which is what `TriageView` does with its piles.
struct MobileListDetailView: View {
    let list: TaskList

    @Environment(MobileEnvironment.self) private var env

    private var tasks: [TaskItem] { env.tasks(in: list.id) }
    private var sections: [ListSection] { env.sections(in: list.id) }

    /// Tasks filed under no section. Shown first and without a heading, exactly as an
    /// unsectioned list looks, so a list with one section does not suddenly grow two.
    private var unsectioned: [TaskItem] {
        let known = Set(sections.map { $0.id.uuidString })
        // A task whose section was deleted on another device before that deletion arrived
        // here still has to appear somewhere. Unfiled is the honest place.
        return tasks.filter { $0.sectionID.map { !known.contains($0) } ?? true }
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "Nothing in this list",
                    systemImage: "checkmark.circle",
                    description: Text("Add something with the + button.")
                )
            } else {
                List {
                    if !unsectioned.isEmpty {
                        Section {
                            ForEach(unsectioned) { task in
                                TaskRow(task: task, showsScheduleActions: true)
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }

                    ForEach(sections) { section in
                        let filed = tasks.filter { $0.sectionID == section.id.uuidString }
                        if !filed.isEmpty {
                            Section {
                                ForEach(filed) { task in
                                    TaskRow(task: task, showsScheduleActions: true)
                                        .listRowInsets(EdgeInsets())
                                }
                            } header: {
                                Text(section.name)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .safeAreaPadding(.bottom, 72)
                .refreshable { await env.store.refresh() }
            }
        }
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.background)
    }
}
