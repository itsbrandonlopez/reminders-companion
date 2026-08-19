import RemindersCore
import SwiftUI

/// Today's dated work, flat. Overdue items are held back in Triage and surfaced here only
/// as a banner — mixing them in is what makes a "today" list stop meaning today.
struct TodayView: View {
    let onShowTriage: () -> Void
    @Environment(MobileEnvironment.self) private var env

    private var tasks: [TaskItem] { env.todaysTasks }
    /// Resolved from `env.pendingTaskID` when a "Next Up" widget deep-links straight to a
    /// specific task rather than just landing on the tab.
    @State private var deepLinkTask: TaskItem?

    var body: some View {
        NavigationStack {
            List {
                if env.backlogCount > 0 {
                    Section {
                        Button(action: onShowTriage) {
                            HStack(spacing: 9) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("\(env.backlogCount) in backlog")
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Palette.overdue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let summary = env.overlaySummary(on: .today()) {
                    Section {
                        Label(summary, systemImage: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                Section {
                    if tasks.isEmpty {
                        ContentUnavailableView(
                            "Nothing planned for today",
                            systemImage: "checkmark.circle",
                            description: Text("Pull something in from Week or Triage.")
                        )
                    } else {
                        ForEach(tasks) { task in
                            TaskRow(task: task)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                } header: {
                    Text(Day.today().monthDayLabel)
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaPadding(.bottom, 72)   // clears the floating add button
            .navigationTitle("Today")
            .refreshable { await env.store.refresh() }
            .task { resolvePendingDeepLink() }
            .onChange(of: env.pendingTaskID) { _, _ in resolvePendingDeepLink() }
            .sheet(item: $deepLinkTask) { task in
                TaskSheet(task: task).environment(env)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // A fresh Simulator has an empty Reminders database, and so does a
                        // new user's account. Both need something to try the app on.
                        if env.store.hasSampleData {
                            Button("Remove Demo Tasks", role: .destructive) {
                                Task { await env.store.removeSampleData() }
                            }
                        } else {
                            Button("Add Demo Tasks") {
                                Task { await env.store.installSampleData() }
                            }
                        }
                        Divider()
                        Button("Refresh") { Task { await env.store.refresh() } }
                        Button("Run Setup Again") { env.restartSetup() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    /// Consumes `env.pendingTaskID` once. If the task isn't loaded yet (a cold launch
    /// racing the first refresh), it is simply not found and the deep link falls back to
    /// having landed on Today, which `RootTabView` already handled.
    private func resolvePendingDeepLink() {
        guard let id = env.pendingTaskID else { return }
        env.pendingTaskID = nil
        deepLinkTask = env.store.tasks.first { $0.id == id }
    }
}
