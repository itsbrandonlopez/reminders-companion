import XCTest
@testable import RemindersCore

/// These cover the rule that Phase 0 turned up the hard way: `allDay` belongs to the
/// reminder, not to each date, so a planned day has to mirror the due date's timed-ness
/// or a timed deadline quietly loses its time. See spike/FINDINGS.md.
final class SchedulingTests: XCTestCase {

    private func timedDue(hour: Int = 9, zone: String = "America/New_York") -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.timeZone = TimeZone(identifier: zone)
        c.year = 2026; c.month = 8; c.day = 20
        c.hour = hour; c.minute = 0; c.second = 0
        return c
    }

    private func allDayDue() -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.year = 2026; c.month = 8; c.day = 20
        return c
    }

    func testIsTimedDistinguishesAllDayFromTimed() {
        XCTAssertTrue(Scheduling.isTimed(timedDue()))
        XCTAssertFalse(Scheduling.isTimed(allDayDue()))
        XCTAssertFalse(Scheduling.isTimed(nil))
    }

    func testPlannedDayAlongsideTimedDueStaysTimed() {
        let planned = Scheduling.plannedComponents(
            for: Day(year: 2026, month: 8, day: 19), alongside: timedDue()
        )
        // Non-nil time components keep the reminder out of all-day mode, which is what
        // stops the 09:00 deadline from being flattened.
        XCTAssertEqual(planned.hour, 0)
        XCTAssertEqual(planned.minute, 0)
        XCTAssertEqual(planned.second, 0)
        XCTAssertEqual(planned.timeZone?.identifier, "America/New_York")
        XCTAssertEqual(planned.year, 2026)
        XCTAssertEqual(planned.day, 19)
    }

    func testPlannedDayAlongsideAllDayDueStaysFloating() {
        let planned = Scheduling.plannedComponents(
            for: Day(year: 2026, month: 8, day: 19), alongside: allDayDue()
        )
        XCTAssertNil(planned.hour)
        XCTAssertNil(planned.minute)
        XCTAssertNil(planned.second)
        // A floating date cannot drift when the machine changes timezone.
        XCTAssertNil(planned.timeZone)
    }

    func testPlannedDayWithNoDueDateIsFloating() {
        let planned = Scheduling.plannedComponents(
            for: Day(year: 2026, month: 8, day: 19), alongside: nil
        )
        XCTAssertNil(planned.hour)
        XCTAssertNil(planned.timeZone)
    }

    func testPlannedComponentsAlwaysCarryGregorianCalendar() {
        // EventKit raises an exception for any other calendar identifier.
        let planned = Scheduling.plannedComponents(for: Day(year: 2026, month: 1, day: 1), alongside: nil)
        XCTAssertEqual(planned.calendar?.identifier, .gregorian)
    }

    func testBoardDayPrefersPlannedOverDue() {
        var start = DateComponents(); start.year = 2026; start.month = 8; start.day = 18
        let due = allDayDue()   // the 20th
        XCTAssertEqual(Scheduling.boardDay(start: start, due: due), Day(year: 2026, month: 8, day: 18))
        XCTAssertEqual(Scheduling.boardDay(start: nil, due: due), Day(year: 2026, month: 8, day: 20))
        XCTAssertNil(Scheduling.boardDay(start: nil, due: nil))
    }

    func testSpanCoversPlannedThroughDue() {
        var start = DateComponents(); start.year = 2026; start.month = 8; start.day = 18
        let span = Scheduling.span(start: start, due: allDayDue())
        XCTAssertEqual(span?.lowerBound, Day(year: 2026, month: 8, day: 18))
        XCTAssertEqual(span?.upperBound, Day(year: 2026, month: 8, day: 20))
    }

    func testSpanNormalisesReversedDates() {
        // A deadline earlier than the planned day is user error, not a crash.
        var start = DateComponents(); start.year = 2026; start.month = 8; start.day = 25
        let span = Scheduling.span(start: start, due: allDayDue())
        XCTAssertEqual(span?.lowerBound, Day(year: 2026, month: 8, day: 20))
        XCTAssertEqual(span?.upperBound, Day(year: 2026, month: 8, day: 25))
    }

    func testSpanIsNilForBacklogItems() {
        XCTAssertNil(Scheduling.span(start: nil, due: nil))
    }

    func testWeekStartsOnMondayAndHasSevenDays() {
        // 2026-08-18 is a Tuesday.
        let week = Scheduling.week(containing: Day(year: 2026, month: 8, day: 18))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, Day(year: 2026, month: 8, day: 17))  // Monday
        XCTAssertEqual(week.last, Day(year: 2026, month: 8, day: 23))   // Sunday
    }

    func testWeekOnItsOwnFirstDayDoesNotJumpBack() {
        let week = Scheduling.week(containing: Day(year: 2026, month: 8, day: 17))
        XCTAssertEqual(week.first, Day(year: 2026, month: 8, day: 17))
    }

    func testWeekHonoursSundayStart() {
        let week = Scheduling.week(containing: Day(year: 2026, month: 8, day: 18), firstWeekday: 1)
        XCTAssertEqual(week.first, Day(year: 2026, month: 8, day: 16))
    }
}

/// The backlog rule, stated precisely: "past due, really past this week. If it's Tuesday
/// and it was due this Monday, leave it on Monday."
final class BucketTests: XCTestCase {

    /// Week of Mon 2026-08-17 … Sun 2026-08-23.
    private let weekStart = Day(year: 2026, month: 8, day: 17)

    func testNoDatesIsUnscheduled() {
        XCTAssertEqual(
            Scheduling.bucket(plannedDay: nil, dueDay: nil, currentWeekStart: weekStart),
            .unscheduled
        )
    }

    func testDueEarlierThisWeekStaysOnItsDay() {
        // Today is Tuesday the 18th; this was due Monday the 17th.
        let monday = Day(year: 2026, month: 8, day: 17)
        XCTAssertEqual(
            Scheduling.bucket(plannedDay: nil, dueDay: monday, currentWeekStart: weekStart),
            .day(monday)
        )
    }

    func testDueBeforeThisWeekIsBacklog() {
        let lastFriday = Day(year: 2026, month: 8, day: 14)
        XCTAssertEqual(
            Scheduling.bucket(plannedDay: nil, dueDay: lastFriday, currentWeekStart: weekStart),
            .backlog
        )
    }

    func testBoundaryIsInclusiveOfTheWeekStart() {
        // The Monday that starts the week is in the week, not behind it.
        XCTAssertEqual(
            Scheduling.bucket(plannedDay: nil, dueDay: weekStart, currentWeekStart: weekStart),
            .day(weekStart)
        )
        XCTAssertEqual(
            Scheduling.bucket(
                plannedDay: nil,
                dueDay: weekStart.adding(days: -1),
                currentWeekStart: weekStart
            ),
            .backlog
        )
    }

    func testFutureWorkIsNeverBacklog() {
        let nextMonth = Day(year: 2026, month: 9, day: 30)
        XCTAssertEqual(
            Scheduling.bucket(plannedDay: nil, dueDay: nextMonth, currentWeekStart: weekStart),
            .day(nextMonth)
        )
    }

    func testPlannedDayWinsOverAnOldDeadline() {
        // A task with a missed deadline that you have since planned for this week belongs
        // on the day you planned it, not in the backlog.
        let planned = Day(year: 2026, month: 8, day: 20)
        let oldDue = Day(year: 2026, month: 8, day: 3)
        XCTAssertEqual(
            Scheduling.bucket(plannedDay: planned, dueDay: oldDue, currentWeekStart: weekStart),
            .day(planned)
        )
    }

    func testPlanningIntoThePastStillFallsToBacklog() {
        let planned = Day(year: 2026, month: 7, day: 1)
        XCTAssertEqual(
            Scheduling.bucket(
                plannedDay: planned,
                dueDay: Day(year: 2026, month: 8, day: 20),
                currentWeekStart: weekStart
            ),
            .backlog
        )
    }
}

/// The deadline end of a multi-day span. This is the only place the app writes a due
/// date, so preserving an existing time of day matters: dragging the span of a bill due
/// Friday 9:00 AM must not flatten it to a bare all-day item.
final class DeadlineComponentsTests: XCTestCase {

    private func timedDue() -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.timeZone = TimeZone(identifier: "America/New_York")
        c.year = 2026; c.month = 8; c.day = 20
        c.hour = 9; c.minute = 30; c.second = 0
        return c
    }

    private func allDayDue() -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.year = 2026; c.month = 8; c.day = 20
        return c
    }

    func testMovingATimedDeadlineKeepsItsTimeOfDay() {
        let moved = Scheduling.deadlineComponents(
            for: Day(year: 2026, month: 8, day: 24), preserving: timedDue()
        )
        XCTAssertEqual(moved.day, 24)
        XCTAssertEqual(moved.hour, 9)
        XCTAssertEqual(moved.minute, 30)
        XCTAssertEqual(moved.timeZone?.identifier, "America/New_York")
    }

    func testMovingAnAllDayDeadlineStaysAllDayAndFloating() {
        let moved = Scheduling.deadlineComponents(
            for: Day(year: 2026, month: 8, day: 24), preserving: allDayDue()
        )
        XCTAssertEqual(moved.day, 24)
        XCTAssertNil(moved.hour)
        XCTAssertNil(moved.timeZone)
    }

    func testCreatingADeadlineWhereNoneExistedIsAllDay() {
        let created = Scheduling.deadlineComponents(
            for: Day(year: 2026, month: 8, day: 24), preserving: nil
        )
        XCTAssertNil(created.hour)
        XCTAssertNil(created.timeZone)
        XCTAssertEqual(created.calendar?.identifier, .gregorian)
    }

    func testDeadlineAlwaysCarriesGregorianCalendar() {
        // EventKit raises for any other calendar identifier.
        let a = Scheduling.deadlineComponents(for: Day(year: 2026, month: 1, day: 1), preserving: timedDue())
        XCTAssertEqual(a.calendar?.identifier, .gregorian)
    }

    func testSpanFromPlannedToNewDeadline() {
        var start = DateComponents(); start.year = 2026; start.month = 8; start.day = 20
        let due = Scheduling.deadlineComponents(
            for: Day(year: 2026, month: 8, day: 24), preserving: nil
        )
        let span = Scheduling.span(start: start, due: due)
        XCTAssertEqual(span?.lowerBound, Day(year: 2026, month: 8, day: 20))
        XCTAssertEqual(span?.upperBound, Day(year: 2026, month: 8, day: 24))
    }
}

/// iOS refuses to save a reminder that has a due date but no start date
/// (`EKErrorNoStartDate`); macOS has no such requirement. These cover the pure logic that
/// decides when to intervene and what to write, so the rule is verifiable on either
/// platform even though it only *applies* on iOS.
final class IOSStartDateRequirementTests: XCTestCase {

    private func components(day: Int, hour: Int? = nil) -> DateComponents {
        var c = DateComponents()
        c.calendar = Day.gregorian
        c.year = 2026; c.month = 8; c.day = day
        if let hour {
            c.timeZone = TimeZone(identifier: "America/New_York")
            c.hour = hour; c.minute = 0; c.second = 0
        }
        return c
    }

    func testDueWithoutStartNeedsIntervention() {
        XCTAssertTrue(Scheduling.needsStartDateForDueDate(due: components(day: 20), start: nil))
    }

    func testDueWithStartIsAlreadyFine() {
        XCTAssertFalse(
            Scheduling.needsStartDateForDueDate(due: components(day: 20), start: components(day: 18))
        )
    }

    func testNoDueDateNeedsNothing() {
        XCTAssertFalse(Scheduling.needsStartDateForDueDate(due: nil, start: nil))
        XCTAssertFalse(Scheduling.needsStartDateForDueDate(due: nil, start: components(day: 18)))
    }

    func testGeneratedStartIsTheDueDayItselfNotToday() {
        // The whole point: planned day must equal the deadline so the task does not move
        // to a different column on iPhone than it occupies on the Mac.
        let start = Scheduling.startDateSatisfyingDueDate(components(day: 20))
        XCTAssertEqual(Day(start), Day(year: 2026, month: 8, day: 20))
    }

    func testGeneratedStartLeavesBoardPositionAndSpanUnchanged() {
        let due = components(day: 20)
        let start = Scheduling.startDateSatisfyingDueDate(due)

        // Same column as it occupied with no start date at all.
        XCTAssertEqual(
            Scheduling.boardDay(start: start, due: due),
            Scheduling.boardDay(start: nil, due: due)
        )
        // And it must not start rendering as a multi-day bar.
        let span = Scheduling.span(start: start, due: due)
        XCTAssertEqual(span?.lowerBound, span?.upperBound)
    }

    func testGeneratedStartMirrorsATimedDeadline() {
        // A timed due date must produce a timed start, or the all-day coercion rule
        // flattens the deadline's time — the trap from the original spike.
        let start = Scheduling.startDateSatisfyingDueDate(components(day: 20, hour: 9))
        XCTAssertEqual(start?.hour, 0)
        XCTAssertEqual(start?.timeZone?.identifier, "America/New_York")
    }

    func testGeneratedStartForAnAllDayDeadlineStaysFloating() {
        let start = Scheduling.startDateSatisfyingDueDate(components(day: 20))
        XCTAssertNil(start?.hour)
        XCTAssertNil(start?.timeZone)
    }

    func testNoDueDateProducesNoStart() {
        XCTAssertNil(Scheduling.startDateSatisfyingDueDate(nil))
    }
}
