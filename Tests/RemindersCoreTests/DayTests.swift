import XCTest
@testable import RemindersCore

final class DayTests: XCTestCase {

    func testInitFromComponentsIgnoresTime() {
        // Reminders reads an all-day start back as 00:00:00, so the time has to be
        // discarded or tasks land in the wrong column.
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 18
        c.hour = 0; c.minute = 0; c.second = 0
        XCTAssertEqual(Day(c), Day(year: 2026, month: 8, day: 18))
    }

    func testInitFromIncompleteComponentsFails() {
        var c = DateComponents(); c.year = 2026; c.month = 8
        XCTAssertNil(Day(c))
        XCTAssertNil(Day(nil))
    }

    func testOrdering() {
        XCTAssertLessThan(Day(year: 2026, month: 8, day: 18), Day(year: 2026, month: 8, day: 19))
        XCTAssertLessThan(Day(year: 2026, month: 8, day: 31), Day(year: 2026, month: 9, day: 1))
        XCTAssertLessThan(Day(year: 2025, month: 12, day: 31), Day(year: 2026, month: 1, day: 1))
    }

    func testAddingDaysCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(Day(year: 2026, month: 8, day: 31).adding(days: 1), Day(year: 2026, month: 9, day: 1))
        XCTAssertEqual(Day(year: 2026, month: 12, day: 31).adding(days: 1), Day(year: 2027, month: 1, day: 1))
        XCTAssertEqual(Day(year: 2026, month: 3, day: 1).adding(days: -1), Day(year: 2026, month: 2, day: 28))
    }

    func testAddingDaysAcrossSpringForwardDST() {
        // US DST begins 2026-03-08. Adding a day must land on the 9th, not 23 hours later.
        XCTAssertEqual(Day(year: 2026, month: 3, day: 7).adding(days: 1), Day(year: 2026, month: 3, day: 8))
        XCTAssertEqual(Day(year: 2026, month: 3, day: 8).adding(days: 1), Day(year: 2026, month: 3, day: 9))
    }

    func testAddingDaysAcrossFallBackDST() {
        // US DST ends 2026-11-01, giving a 25-hour day.
        XCTAssertEqual(Day(year: 2026, month: 11, day: 1).adding(days: 1), Day(year: 2026, month: 11, day: 2))
    }

    func testLeapDay() {
        XCTAssertEqual(Day(year: 2028, month: 2, day: 28).adding(days: 1), Day(year: 2028, month: 2, day: 29))
        XCTAssertEqual(Day(year: 2026, month: 2, day: 28).adding(days: 1), Day(year: 2026, month: 3, day: 1))
    }

    func testDescription() {
        XCTAssertEqual(Day(year: 2026, month: 8, day: 3).description, "2026-08-03")
    }
}
