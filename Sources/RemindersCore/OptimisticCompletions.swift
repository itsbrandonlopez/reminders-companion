import Foundation

/// Tracks tasks tapped on the Watch that the iPhone has not yet confirmed.
///
/// The Watch cannot write to EventKit, so completing is a request sent to the phone. The
/// real round trip is phone-writes → iCloud → this watch re-syncs, which is not instant
/// and can be minutes when the phone is out of range. Hiding the row immediately is what
/// keeps the app from feeling broken while it is working correctly.
///
/// Lives here rather than in the watch target so this reconciliation — the one piece of
/// genuinely watch-specific logic — is unit-testable. A watchOS simulator has an empty
/// Reminders database that nothing can seed, so it cannot be verified on-device.
public struct OptimisticCompletions: Equatable, Sendable {
    private var pending: Set<String> = []

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }
    public var count: Int { pending.count }

    public mutating func markCompleted(_ taskID: String) {
        pending.insert(taskID)
    }

    public func hides(_ taskID: String) -> Bool { pending.contains(taskID) }

    /// Filters a freshly fetched list down to what the user should still see.
    public func visible(in tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { !pending.contains($0.id) }
    }

    /// Drops entries the server has caught up on.
    ///
    /// A task still present in a fresh fetch is still incomplete, so it stays hidden. One
    /// that has *left* the fetch is genuinely done and no longer needs suppressing —
    /// keeping it would leak memory and, worse, permanently hide the task if it were ever
    /// un-completed elsewhere.
    public mutating func reconcile(against freshTasks: [TaskItem]) {
        pending.formIntersection(Set(freshTasks.map(\.id)))
    }

    /// Clears a single entry, for when a request is known to have failed and the row
    /// should come back rather than stay invisible.
    public mutating func restore(_ taskID: String) {
        pending.remove(taskID)
    }
}
