import XCTest
@testable import RemindersCore

/// Event bucketing is all about the end boundary. An all-day event ends at midnight on
/// the *following* day, and a gig that runs until midnight must not paint the next
/// morning's column — both would otherwise show a spurious extra busy day.
final class CalendarEventTests: XCTestCase {

    private let zone = TimeZone(identifier: "America/New_York")!

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func event(
        start: Date, end: Date, allDay: Bool = false, title: String = "Gig"
    ) -> CalendarEvent {
        CalendarEvent(
            id: "e", title: title, start: start, end: end, isAllDay: allDay,
            calendarID: "c", calendarName: "Work", color: .neutral
        )
    }

    func testTimedEventWithinOneDay() {
        let e = event(start: date(8, 20, 9), end: date(8, 20, 17))
        XCTAssertEqual(e.days(in: zone), Day(year: 2026, month: 8, day: 20)...Day(year: 2026, month: 8, day: 20))
        XCTAssertTrue(e.occupies(Day(year: 2026, month: 8, day: 20), in: zone))
        XCTAssertFalse(e.occupies(Day(year: 2026, month: 8, day: 21), in: zone))
    }

    func testEventEndingExactlyAtMidnightDoesNotClaimTheNextDay() {
        let e = event(start: date(8, 20, 17), end: date(8, 21, 0))
        XCTAssertFalse(e.occupies(Day(year: 2026, month: 8, day: 21), in: zone))
        XCTAssertEqual(e.days(in: zone).upperBound, Day(year: 2026, month: 8, day: 20))
    }

    func testEventCrossingMidnightClaimsBothDays() {
        let e = event(start: date(8, 20, 22), end: date(8, 21, 2))
        XCTAssertTrue(e.occupies(Day(year: 2026, month: 8, day: 20), in: zone))
        XCTAssertTrue(e.occupies(Day(year: 2026, month: 8, day: 21), in: zone))
    }

    func testSingleAllDayEventCoversOneDayOnly() {
        // EventKit reports an all-day event as midnight-to-midnight of the next day.
        let e = event(start: date(8, 20), end: date(8, 21), allDay: true)
        XCTAssertEqual(e.days(in: zone), Day(year: 2026, month: 8, day: 20)...Day(year: 2026, month: 8, day: 20))
    }

    func testMultiDayAllDayEventCoversItsRealSpan() {
        let e = event(start: date(8, 20), end: date(8, 23), allDay: true)
        XCTAssertEqual(
            e.days(in: zone),
            Day(year: 2026, month: 8, day: 20)...Day(year: 2026, month: 8, day: 22)
        )
    }

    func testZeroDurationEventStillOccupiesItsDay() {
        let e = event(start: date(8, 20, 14), end: date(8, 20, 14))
        XCTAssertTrue(e.occupies(Day(year: 2026, month: 8, day: 20), in: zone))
    }

    func testInvertedDatesDoNotCrash() {
        let e = event(start: date(8, 20, 14), end: date(8, 19, 9))
        XCTAssertEqual(e.days(in: zone).lowerBound, Day(year: 2026, month: 8, day: 20))
    }

    func testDurationMinutes() {
        XCTAssertEqual(event(start: date(8, 20, 9), end: date(8, 20, 17)).durationMinutes, 480)
        XCTAssertEqual(event(start: date(8, 20, 9), end: date(8, 20, 9)).durationMinutes, 0)
    }

    func testTimeLabelForSingleDayEventShowsBothEnds() {
        let e = event(start: date(8, 20, 9), end: date(8, 20, 17))
        XCTAssertEqual(e.timeLabel(on: Day(year: 2026, month: 8, day: 20), in: zone), "9:00 AM – 5:00 PM")
    }

    func testTimeLabelSplitsAcrossDays() {
        let e = event(start: date(8, 20, 22), end: date(8, 21, 2))
        XCTAssertEqual(e.timeLabel(on: Day(year: 2026, month: 8, day: 20), in: zone), "from 10:00 PM")
        XCTAssertEqual(e.timeLabel(on: Day(year: 2026, month: 8, day: 21), in: zone), "until 2:00 AM")
    }

    func testTimeLabelForMiddleOfALongEvent() {
        let e = event(start: date(8, 18, 9), end: date(8, 22, 17))
        XCTAssertEqual(e.timeLabel(on: Day(year: 2026, month: 8, day: 20), in: zone), "All day")
    }

    func testAllDayLabel() {
        let e = event(start: date(8, 20), end: date(8, 21), allDay: true)
        XCTAssertEqual(e.timeLabel(on: Day(year: 2026, month: 8, day: 20), in: zone), "All day")
    }
}
