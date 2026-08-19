import Foundation

/// `TimelineProvider`'s completion-handler methods predate Swift's strict concurrency and
/// are not `Sendable`, so capturing one inside a `Task` to bridge to async data fetching is
/// flagged as a data-race risk. Boxing it is safe in practice: the closure is called exactly
/// once, from that `Task`, and never touched anywhere else.
///
/// Shared by the iOS and watchOS widget extensions. It was briefly duplicated in both —
/// which meant a future tightening of what `@unchecked Sendable` permits could have been
/// fixed in one copy and silently left unsound in the other.
public struct SendableCompletion<T>: @unchecked Sendable {
    public let run: (T) -> Void

    public init(run: @escaping (T) -> Void) {
        self.run = run
    }
}
