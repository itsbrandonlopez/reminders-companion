import AppIntents
import EventKit
import RemindersCore
import WidgetKit

/// Completes a task from a tap on the widget, with no app launch.
///
/// Calls `ReminderStore.completeReminder`, the same static function a diagnostic verifies
/// against a disposable list before this ships — the widget and that verification run the
/// identical code path, not merely similar ones.
struct CompleteTaskIntent: AppIntent {
    // Computed, not stored — a `static var` with an initial value is flagged under Swift 6
    // strict concurrency as global mutable state, even though nothing here ever mutates it.
    static var title: LocalizedStringResource { "Complete Task" }
    static var description: IntentDescription {
        IntentDescription("Marks a reminder as completed.")
    }

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let store = EKEventStore()
        _ = try? ReminderStore.completeReminder(externalID: taskID, in: store)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextUp)
        return .result()
    }
}
