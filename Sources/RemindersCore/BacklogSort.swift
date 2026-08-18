import Foundation

/// How a backlog is ordered.
///
/// Oldest first is the default: the thing that has been waiting longest is the thing most
/// likely to be quietly rotting. Newest first is for the opposite read — what did I just
/// let slip?
public enum BacklogSort: String, CaseIterable, Sendable {
    case oldestFirst
    case newestFirst

    public var label: String {
        switch self {
        case .oldestFirst: "Oldest first"
        case .newestFirst: "Newest first"
        }
    }

    public var symbol: String {
        switch self {
        case .oldestFirst: "arrow.up"
        case .newestFirst: "arrow.down"
        }
    }
}

extension BacklogSort {
    /// Orders a backlog by how long each item has been waiting.
    ///
    /// Ties fall back to priority, so a same-day pile still leads with what matters.
    /// Undated items sort last in both directions — they have no age to compare.
    public func sort(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch (lhs.boardDay, rhs.boardDay) {
            case let (.some(l), .some(r)) where l != r:
                return self == .oldestFirst ? l < r : l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.priority.sortWeight < rhs.priority.sortWeight
            }
        }
    }
}
