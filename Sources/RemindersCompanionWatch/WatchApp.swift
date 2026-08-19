import RemindersCore
import RemindersShared
import SwiftUI

@main
struct RemindersCompanionWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTodayView()
        }
    }
}

/// Today's tasks on the wrist.
///
/// Reads through `WidgetDataProvider` — already the sidecar-free, bare-`EKEventStore` path
/// built for the widget extension, and exactly what a watch needs. Nothing here writes:
/// watchOS EventKit is read-only, so completing sends a request to the iPhone.
@MainActor
@Observable
final class WatchModel {
    private(set) var tasks: [TaskItem] = []
    private(set) var isLoading = true
    private(set) var isAuthorized = true

    /// Tapped-but-unconfirmed completions. The reconciliation logic lives in
    /// `OptimisticCompletions` in RemindersCore so it can be unit-tested — a watchOS
    /// simulator's Reminders database is empty and unseedable, so this is the only way to
    /// verify it.
    private var optimistic = OptimisticCompletions()

    var visibleTasks: [TaskItem] { optimistic.visible(in: tasks) }

    func load() async {
        isAuthorized = WidgetDataProvider.authorizationStatus() == .fullAccess
        guard isAuthorized else { isLoading = false; return }
        tasks = await WidgetDataProvider.fetchToday()
        optimistic.reconcile(against: tasks)
        isLoading = false
    }

    func complete(_ task: TaskItem) {
        optimistic.markCompleted(task.id)
        WatchBridge.shared.requestComplete(taskID: task.id)
    }
}

struct WatchTodayView: View {
    @State private var model = WatchModel()

    var body: some View {
        NavigationStack {
            Group {
                if !model.isAuthorized {
                    unauthorized
                } else if model.isLoading {
                    ProgressView()
                } else if model.visibleTasks.isEmpty {
                    ContentUnavailableView(
                        "All clear",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing left for today.")
                    )
                } else {
                    List(model.visibleTasks) { task in
                        WatchTaskRow(task: task) { model.complete(task) }
                    }
                }
            }
            .navigationTitle("Today")
        }
        .task {
            WatchBridge.shared.activate()
            await model.load()
        }
    }

    private var unauthorized: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist").font(.title2)
            Text("Allow Reminders access on your iPhone")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
