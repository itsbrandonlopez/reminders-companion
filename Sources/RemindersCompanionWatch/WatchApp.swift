import RemindersCore
import RemindersShared
import SwiftUI
import WidgetKit

@main
struct RemindersCompanionWatchApp: App {
    init() {
        // Activated up front so the session is ready before the first tap, rather than
        // racing the view's appearance.
        WatchBridge.shared.activate()
    }

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
        // Request rather than merely check: a watch has its own TCC grant, and there is no
        // Settings pane on the watch to turn it on afterwards. Checking alone would strand
        // every new user on the unauthorised screen with nothing to tap.
        isAuthorized = await WidgetDataProvider.requestAccess()
        guard isAuthorized else { isLoading = false; return }
        tasks = await WidgetDataProvider.fetchToday()
        optimistic.reconcile(against: tasks)
        isLoading = false
    }

    /// Re-reads without the full loading state, for coming back to an already-open app.
    func refresh() async {
        guard isAuthorized else { return }
        tasks = await WidgetDataProvider.fetchToday()
        optimistic.reconcile(against: tasks)
    }

    func complete(_ task: TaskItem) {
        optimistic.markCompleted(task.id)
        WatchBridge.shared.requestComplete(taskID: task.id)
        // The complication shows a count taken from the same data; without this it keeps
        // the old number until watchOS happens to refresh on its own budget.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.watchToday)
    }
}

struct WatchTodayView: View {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

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
            await model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            // Raising your wrist resumes rather than recreates the app, so `.task` does
            // not fire again — without this the list is whatever it was at first launch,
            // and tapping a task already completed elsewhere sends a pointless request.
            guard phase == .active else { return }
            Task { await model.refresh() }
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
