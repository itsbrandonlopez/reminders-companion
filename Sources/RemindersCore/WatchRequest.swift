import Foundation

/// Carries a write request from the Watch to the iPhone.
///
/// watchOS EventKit is read-only, so the Watch can never complete a task itself. It asks
/// the phone to, and the phone runs the same `ReminderStore.completeReminder` the widget's
/// intent uses — one completion path shared by every surface rather than several that
/// drift apart.
///
/// Lives in `RemindersCore`, not in `RemindersShared` beside the `WCSession` wrapper that
/// sends it. The wrapper genuinely needs WatchConnectivity and so is iOS/watchOS-only; this
/// is a dictionary shape and needs nothing. Keeping it there meant `WatchRequestTests` could
/// not import it, so it re-declared the keys and re-implemented `parse` — and every one of
/// those tests passed no matter what this file said. The whole point of pinning a contract
/// that crosses a device boundary is that a typo becomes a test failure rather than a
/// silently ignored completion.
public enum WatchRequest {
    public static let actionKey = "action"
    public static let taskIDKey = "taskID"
    public static let requestIDKey = "requestID"
    public static let completeAction = "complete"

    public static func complete(taskID: String, requestID: String = UUID().uuidString) -> [String: Any] {
        [actionKey: completeAction, taskIDKey: taskID, requestIDKey: requestID]
    }

    /// Returns the task id and the request's own id when the payload is a well-formed
    /// completion request.
    ///
    /// The request id exists because a `sendMessage` whose *acknowledgement* fails is
    /// retried over the queue, so the phone can receive the same request twice. Completing
    /// twice is harmless today, but this envelope is built to carry more actions and the
    /// first non-idempotent one (reschedule, delete) would otherwise execute twice.
    public static func parse(_ payload: [String: Any]) -> (taskID: String, requestID: String)? {
        guard payload[actionKey] as? String == completeAction,
              let id = payload[taskIDKey] as? String, !id.isEmpty else { return nil }
        // Tolerate a missing request id so an older watch build still works; fall back to
        // the task id, which at least dedupes repeats of the same completion.
        let requestID = (payload[requestIDKey] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return (id, requestID)
    }
}
