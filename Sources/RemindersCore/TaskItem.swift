import Foundation

public struct RGBA: Hashable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let neutral = RGBA(red: 0.55, green: 0.55, blue: 0.58)
}

public struct TaskList: Identifiable, Hashable, Sendable {
    public let id: String          // EKCalendar.calendarIdentifier
    public let title: String
    public let color: RGBA
    public let isEditable: Bool
    public let isDefault: Bool     // where Siri drops new reminders

    public init(id: String, title: String, color: RGBA, isEditable: Bool, isDefault: Bool) {
        self.id = id; self.title = title; self.color = color
        self.isEditable = isEditable; self.isDefault = isDefault
    }
}

public enum Priority: Int, CaseIterable, Sendable {
    case none = 0, high = 1, medium = 5, low = 9

    /// Reminders only accepts 0–9 and buckets them per RFC 5545: 1–4 high, 5 medium,
    /// 6–9 low. Values written by other clients get folded into the nearest bucket.
    public init(reminderValue: Int) {
        switch reminderValue {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var label: String {
        switch self {
        case .none: "None"; case .high: "High"; case .medium: "Medium"; case .low: "Low"
        }
    }

    /// Highest first, with unprioritised tasks last.
    public var sortWeight: Int {
        switch self {
        case .high: 0; case .medium: 1; case .low: 2; case .none: 3
        }
    }
}

/// A flattened, value-type view of an `EKReminder` merged with its sidecar row.
///
/// Views never touch EventKit objects directly. `EKReminder` is a live, mutable
/// reference tied to a specific `EKEventStore`, and the fetch → mutate → refetch cycle
/// makes it a poor fit for SwiftUI state — holding one across a refetch gives you a
/// stale object attached to a store that has moved on.
public struct TaskItem: Identifiable, Hashable, Sendable {
    /// `calendarItemExternalIdentifier`. The item identifier is documented as not
    /// sync-proof, so it is never used as a key.
    public let id: String
    public var title: String
    public var notes: String?
    public var url: URL?
    public var listID: String
    public var listName: String
    public var listColor: RGBA
    public var priority: Priority
    public var isCompleted: Bool
    public var hasAlarms: Bool
    public var isRecurring: Bool
    /// Every alarm on the reminder, classified by whether this app can express it.
    public var alarms: [AlarmShape]
    /// The repeat rule, if any, and whether it is safe to edit here.
    public var recurrence: RecurrenceShape?

    /// The planned day — `startDateComponents`. What dragging a card writes.
    public var plannedDay: Day?
    /// The real deadline — `dueDateComponents`. Never written by scheduling.
    public var dueDay: Day?
    /// Whether the due date carries a wall-clock time. Drives the all-day coercion rule
    /// in `Scheduling.plannedComponents(for:alongside:)`.
    public var dueIsTimed: Bool
    public var dueDate: Date?

    // Sidecar-only fields.
    public var rank: Double
    public var estimateMinutes: Int?

    public init(
        id: String, title: String, notes: String? = nil, url: URL? = nil,
        listID: String, listName: String, listColor: RGBA,
        priority: Priority = .none, isCompleted: Bool = false,
        hasAlarms: Bool = false, isRecurring: Bool = false,
        alarms: [AlarmShape] = [], recurrence: RecurrenceShape? = nil,
        plannedDay: Day? = nil, dueDay: Day? = nil, dueIsTimed: Bool = false,
        dueDate: Date? = nil, rank: Double = 0, estimateMinutes: Int? = nil
    ) {
        self.id = id; self.title = title; self.notes = notes; self.url = url
        self.listID = listID; self.listName = listName; self.listColor = listColor
        self.priority = priority; self.isCompleted = isCompleted
        self.hasAlarms = hasAlarms; self.isRecurring = isRecurring
        self.alarms = alarms; self.recurrence = recurrence
        self.plannedDay = plannedDay; self.dueDay = dueDay; self.dueIsTimed = dueIsTimed
        self.dueDate = dueDate; self.rank = rank; self.estimateMinutes = estimateMinutes
    }

    public var hasNotes: Bool { !(notes ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    /// The wall-clock time on the deadline, when it has one. This is the detail that
    /// matters on a bill and that a day column alone cannot convey.
    public var dueTimeLabel: String? {
        guard dueIsTimed, let dueDate else { return nil }
        return DateLabels.time.string(from: dueDate)
    }

    /// Where this task sits on the board: planned day if set, else its deadline.
    public var boardDay: Day? { plannedDay ?? dueDay }

    /// Tasks with no dates at all. These are invisible to a bounded date predicate,
    /// which is why the store fetches everything incomplete and partitions in memory.
    public var isBacklog: Bool { plannedDay == nil && dueDay == nil }

    /// A deadline that has already passed, ignoring anything about planning.
    public func isOverdue(asOf today: Day = .today()) -> Bool {
        guard let dueDay, !isCompleted else { return false }
        return dueDay < today
    }

    /// True when the task is planned for one day but due on another — the case the
    /// start/due split exists to represent.
    public var spansMultipleDays: Bool {
        guard let plannedDay, let dueDay else { return false }
        return plannedDay != dueDay
    }

    public var span: ClosedRange<Day>? {
        switch (plannedDay, dueDay) {
        case let (.some(p), .some(d)): return p <= d ? p...d : d...p
        case let (.some(p), .none): return p...p
        case let (.none, .some(d)): return d...d
        case (.none, .none): return nil
        }
    }
}
