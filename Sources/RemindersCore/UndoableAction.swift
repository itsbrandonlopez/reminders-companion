import Foundation

/// The last reversible thing the user did, and how to describe it.
///
/// Deliberately a single slot rather than a stack. Every edit here writes straight through
/// to Reminders, which other devices and the Reminders app itself may be changing at the
/// same time — a deep stack would accumulate entries whose original state has since been
/// overwritten elsewhere, and "undo" would start meaning "overwrite whatever is there
/// now with something stale". One step back is honest about what can actually be
/// guaranteed.
public enum UndoableAction: Hashable, Sendable {
    /// The task, and the planned day it had *before* the move.
    case reschedule(task: TaskItem, previousDay: Day?)
    /// The task, and the deadline it had before.
    case deadline(task: TaskItem, previousDue: Day?)
    /// The task, and the list it came from.
    case move(task: TaskItem, previousListID: String, previousListName: String)
    case complete(task: TaskItem)

    public var task: TaskItem {
        switch self {
        case let .reschedule(task, _), let .deadline(task, _),
             let .move(task, _, _), let .complete(task):
            return task
        }
    }

    /// Phrased as what happened, so the banner reads "Moved to Thursday · Undo".
    public var label: String {
        switch self {
        case let .reschedule(_, previous):
            return previous == nil ? "Scheduled" : "Moved"
        case .deadline:
            return "Deadline changed"
        case let .move(_, _, name):
            return "Moved from \(name)"
        case .complete:
            return "Completed"
        }
    }
}
