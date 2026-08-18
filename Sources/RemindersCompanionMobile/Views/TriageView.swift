import RemindersCore
import SwiftUI

/// The two piles that would otherwise clog Today and Week.
///
/// Rescheduling here is by swipe and menu rather than drag, because a drag cannot cross
/// tab boundaries — the target day lives in a different tab entirely.
struct TriageView: View {
    @Environment(MobileEnvironment.self) private var env

    enum Pile: String, CaseIterable, Identifiable {
        case backlog = "Past Due"
        case unscheduled = "No Date"
        var id: String { rawValue }
    }

    @State private var pile: Pile = .backlog

    private var tasks: [TaskItem] {
        pile == .backlog ? env.backlog : env.unscheduled
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Pile", selection: $pile) {
                    ForEach(Pile.allCases) { p in
                        Text("\(p.rawValue) (\(p == .backlog ? env.backlog.count : env.unscheduled.count))")
                            .tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.surface)

                Divider()

                if tasks.isEmpty {
                    ContentUnavailableView(
                        pile == .backlog ? "Nothing past due" : "Nothing waiting",
                        systemImage: pile == .backlog ? "checkmark.circle" : "tray",
                        description: Text(pile == .backlog
                                          ? "Work that slips past a whole week shows up here."
                                          : "Tasks with no date at all collect here.")
                    )
                    .frame(maxHeight: .infinity)
                    .background(Palette.background)
                } else {
                    List {
                        ForEach(tasks) { task in
                            TaskRow(task: task, showsScheduleActions: true)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await env.store.refresh() }
                }
            }
            .navigationTitle("Triage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if pile == .backlog, !env.backlog.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("All to Today") {
                            Task { await env.store.schedule(env.backlog, to: .today()) }
                        }
                    }
                }
            }
        }
    }
}
