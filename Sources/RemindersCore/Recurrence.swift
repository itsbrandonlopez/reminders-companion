import Foundation

public enum RecurrenceFrequency: String, CaseIterable, Hashable, Sendable {
    case daily, weekly, monthly, yearly

    public var label: String {
        switch self {
        case .daily: "Daily"; case .weekly: "Weekly"
        case .monthly: "Monthly"; case .yearly: "Yearly"
        }
    }
}

public enum RecurrenceEnd: Hashable, Sendable {
    case never
    case onDate(Day)
    case afterCount(Int)
}

/// A repeat rule this app can express end to end.
public struct SimpleRecurrence: Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    public var interval: Int
    public var end: RecurrenceEnd

    public init(frequency: RecurrenceFrequency, interval: Int = 1, end: RecurrenceEnd = .never) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.end = end
    }

    /// "Every 2 weeks", "Daily", "Monthly until 3 Sep".
    public var label: String {
        let base = interval == 1
            ? frequency.label
            : "Every \(interval) \(frequency.unitPlural)"
        switch end {
        case .never: return base
        case let .onDate(day): return "\(base) until \(day.monthDayYear)"
        case let .afterCount(n): return "\(base), \(n) time\(n == 1 ? "" : "s")"
        }
    }
}

/// The shape of whatever repeat rule a reminder currently carries.
///
/// `EKRecurrenceRule` can also specify days of the week, days of the month, months of the
/// year, weeks of the year, days of the year and set positions — "the second Tuesday of
/// every month" and similar. This app's editor expresses frequency, interval and an end
/// only, so a rule using any of those extras is **deliberately not editable here**: writing
/// our simpler rule over it would quietly discard the part we cannot represent, and the
/// user would have no way to know until the reminder failed to fire when expected.
public struct RecurrenceShape: Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    public var interval: Int
    public var end: RecurrenceEnd
    /// True when the rule carries any specifier beyond frequency/interval/end.
    public var hasPositionalSpecifiers: Bool

    public init(
        frequency: RecurrenceFrequency,
        interval: Int,
        end: RecurrenceEnd,
        hasPositionalSpecifiers: Bool
    ) {
        self.frequency = frequency
        self.interval = interval
        self.end = end
        self.hasPositionalSpecifiers = hasPositionalSpecifiers
    }

    /// Whether this app may safely replace the rule without losing information.
    public var isEditableHere: Bool { !hasPositionalSpecifiers }

    public var simple: SimpleRecurrence? {
        guard isEditableHere else { return nil }
        return SimpleRecurrence(frequency: frequency, interval: interval, end: end)
    }

    public var label: String {
        SimpleRecurrence(frequency: frequency, interval: interval, end: end).label
    }
}

extension RecurrenceFrequency {
    var unitPlural: String {
        switch self {
        case .daily: "days"; case .weekly: "weeks"
        case .monthly: "months"; case .yearly: "years"
        }
    }
}

extension Day {
    var monthDayYear: String {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return f.string(from: startOfDay())
    }
}

/// What kind of alarm a reminder carries.
///
/// Absolute and relative alarms are fully expressible here. A location alarm is a geofence
/// — `EKStructuredLocation` with coordinates, a radius and an enter/leave proximity — which
/// this app has no UI to build, so it is shown but never overwritten.
public enum AlarmShape: Hashable, Sendable {
    case absolute(Date)
    case relative(TimeInterval)
    case location(title: String, isEntering: Bool)

    public var isEditableHere: Bool {
        switch self {
        case .absolute, .relative: return true
        case .location: return false
        }
    }

    public var label: String {
        switch self {
        case let .absolute(date):
            let f = DateFormatter()
            f.dateFormat = "d MMM, h:mm a"
            return f.string(from: date)
        case let .relative(offset):
            let minutes = Int(abs(offset) / 60)
            if minutes == 0 { return "At the due time" }
            if minutes % 1440 == 0 { return "\(minutes / 1440)d before" }
            if minutes % 60 == 0 { return "\(minutes / 60)h before" }
            return "\(minutes)m before"
        case let .location(title, isEntering):
            return "\(isEntering ? "Arriving at" : "Leaving") \(title)"
        }
    }
}
