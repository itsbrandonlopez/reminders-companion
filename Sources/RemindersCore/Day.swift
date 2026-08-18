import Foundation

/// A calendar day with no time and no timezone — the unit the week board deals in.
///
/// Reminders reads back an all-day start date as `00:00:00` rather than as a bare
/// year/month/day (see spike/FINDINGS.md), so day bucketing has to compare the date
/// parts and ignore whatever time component came along for the ride.
public struct Day: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// EventKit raises if date components carry a non-Gregorian calendar, and every
    /// date we read or write goes through here, so Gregorian is hard-coded on purpose.
    public static let gregorian = Calendar(identifier: .gregorian)

    public init?(_ components: DateComponents?) {
        guard let c = components, let y = c.year, let m = c.month, let d = c.day else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(_ date: Date, in calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Midnight on this day in the given timezone. Used for sorting and layout only —
    /// never written back to EventKit, which always receives date components.
    public func startOfDay(in timeZone: TimeZone = .current) -> Date {
        var cal = Day.gregorian
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int) -> Day {
        var cal = Day.gregorian
        cal.timeZone = .current
        let base = startOfDay()
        return Day(cal.date(byAdding: .day, value: days, to: base) ?? base)
    }

    public static func today() -> Day { Day(Date()) }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Day: CustomStringConvertible {
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}
