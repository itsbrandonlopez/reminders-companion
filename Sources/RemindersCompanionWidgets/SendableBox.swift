import Foundation

/// `TimelineProvider`'s completion-handler methods predate Swift's strict concurrency and
/// aren't `Sendable`, so capturing one inside a `Task { }` to bridge to `async` data
/// fetching is flagged as a data race risk. Boxing it is safe in practice: the closure is
/// called exactly once, from the `Task`, and never touched anywhere else — the same
/// pattern `ReminderStore` already uses for EventKit's own non-Sendable callbacks.
struct SendableCompletion<T>: @unchecked Sendable {
    let run: (T) -> Void
}
