import Foundation

/// One task and the planned day it held before a bulk reschedule.
public struct PreviousSchedule: Hashable, Sendable {
    public let task: TaskItem
    public let previousDay: Day?

    public init(task: TaskItem, previousDay: Day?) {
        self.task = task
        self.previousDay = previousDay
    }
}

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
    /// "Move All to Today" and friends — every task's prior day, so all of them come back.
    case bulkReschedule(items: [PreviousSchedule])

    /// The subject of the action. For a bulk reschedule this is the first task, used only
    /// as a stable identity for the banner; `label` is what actually describes it.
    public var task: TaskItem? {
        switch self {
        case let .reschedule(task, _), let .deadline(task, _),
             let .move(task, _, _), let .complete(task):
            return task
        case let .bulkReschedule(items):
            return items.first?.task
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
        case let .bulkReschedule(items):
            return "Moved \(items.count) task\(items.count == 1 ? "" : "s")"
        }
    }

    /// Whether this action refers to the given task, so a delete can retire an undo it
    /// would no longer be able to perform.
    public func involves(_ taskID: String) -> Bool {
        switch self {
        case let .bulkReschedule(items):
            return items.contains { $0.task.id == taskID }
        default:
            return task?.id == taskID
        }
    }

    /// What the banner shows beneath the label. A bulk move has no single title to name.
    public var subtitle: String? {
        switch self {
        case .bulkReschedule: return nil
        default: return task?.title
        }
    }
}
