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
    /// How long a tap may stay unconfirmed before the row is shown again.
    ///
    /// Without an expiry, "still present in the fetch" is indistinguishable between *the
    /// write has not arrived yet* and *the write is never going to arrive*, and a
    /// completion that genuinely failed would hide its row for the rest of the session
    /// with no retry. Ten minutes is comfortably longer than a normal queued delivery and
    /// short enough that a lost request comes back while the user still remembers it.
    public static let expiry: TimeInterval = 600

    private var pending: [String: Date] = [:]

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }
    public var count: Int { pending.count }

    public mutating func markCompleted(_ taskID: String, at now: Date = .now) {
        pending[taskID] = now
    }

    public func hides(_ taskID: String, at now: Date = .now) -> Bool {
        guard let markedAt = pending[taskID] else { return false }
        return now.timeIntervalSince(markedAt) < Self.expiry
    }

    /// Filters a freshly fetched list down to what the user should still see.
    public func visible(in tasks: [TaskItem], at now: Date = .now) -> [TaskItem] {
        tasks.filter { !hides($0.id, at: now) }
    }

    /// Drops entries that are finished with, in either direction.
    ///
    /// A task that has *left* the fetch is genuinely completed, so its entry is dead weight
    /// — and keeping it would permanently hide the task if it were ever un-completed
    /// elsewhere. A task still in the fetch is normally just awaiting the write, so it
    /// stays hidden — but only until `expiry`, after which the request is presumed lost and
    /// the row returns so it can be tapped again.
    public mutating func reconcile(against freshTasks: [TaskItem], at now: Date = .now) {
        let live = Set(freshTasks.map(\.id))
        pending = pending.filter { id, markedAt in
            live.contains(id) && now.timeIntervalSince(markedAt) < Self.expiry
        }
    }

    /// Clears a single entry, for when a request is known to have failed and the row
    /// should come back immediately rather than waiting out the expiry.
    public mutating func restore(_ taskID: String) {
        pending.removeValue(forKey: taskID)
    }
}
