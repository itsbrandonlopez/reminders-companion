import XCTest
@testable import RemindersCore

/// The guard that matters here is `isEditableHere`. An `EKRecurrenceRule` can specify days
/// of the week, set positions and more; this app's editor only expresses frequency,
/// interval and an end. Letting it overwrite a richer rule would silently turn "the second
/// Tuesday of every month" into "every 2 months", with nothing on screen to reveal the loss.
final class RecurrenceTests: XCTestCase {

    func testSimpleRuleIsEditable() {
        let shape = RecurrenceShape(
            frequency: .weekly, interval: 2, end: .never, hasPositionalSpecifiers: false
        )
        XCTAssertTrue(shape.isEditableHere)
        XCTAssertEqual(shape.simple, SimpleRecurrence(frequency: .weekly, interval: 2))
    }

    func testPositionalRuleIsNotEditableAndYieldsNoSimpleForm() {
        let shape = RecurrenceShape(
            frequency: .monthly, interval: 1, end: .never, hasPositionalSpecifiers: true
        )
        XCTAssertFalse(shape.isEditableHere)
        XCTAssertNil(shape.simple, "a rule we cannot express must not offer a lossy stand-in")
    }

    /// A positional rule is still described to the user — it is shown, just not editable.
    func testPositionalRuleStillHasALabel() {
        let shape = RecurrenceShape(
            frequency: .monthly, interval: 1, end: .never, hasPositionalSpecifiers: true
        )
        XCTAssertFalse(shape.label.isEmpty)
    }

    func testLabels() {
        XCTAssertEqual(SimpleRecurrence(frequency: .daily).label, "Daily")
        XCTAssertEqual(SimpleRecurrence(frequency: .weekly, interval: 2).label, "Every 2 weeks")
        XCTAssertEqual(SimpleRecurrence(frequency: .monthly, interval: 3).label, "Every 3 months")
        XCTAssertEqual(
            SimpleRecurrence(frequency: .daily, interval: 1, end: .afterCount(5)).label,
            "Daily, 5 times"
        )
        XCTAssertEqual(
            SimpleRecurrence(frequency: .daily, interval: 1, end: .afterCount(1)).label,
            "Daily, 1 time"
        )
    }

    func testEndDateAppearsInTheLabel() {
        let label = SimpleRecurrence(
            frequency: .weekly, end: .onDate(Day(year: 2026, month: 9, day: 3))
        ).label
        XCTAssertTrue(label.contains("until"), label)
        XCTAssertTrue(label.contains("2026"), label)
    }

    /// EventKit rejects an interval below 1; clamping in the initialiser means no caller
    /// can construct one.
    func testIntervalIsClampedToAtLeastOne() {
        XCTAssertEqual(SimpleRecurrence(frequency: .daily, interval: 0).interval, 1)
        XCTAssertEqual(SimpleRecurrence(frequency: .daily, interval: -5).interval, 1)
    }
}

final class AlarmShapeTests: XCTestCase {

    func testTimeBasedAlarmsAreEditable() {
        XCTAssertTrue(AlarmShape.absolute(Date()).isEditableHere)
        XCTAssertTrue(AlarmShape.relative(-3600).isEditableHere)
    }

    /// A geofence carries coordinates and a radius this app has no UI to build, so it is
    /// displayed and left alone rather than replaced by a time-based alarm.
    func testLocationAlarmIsNotEditable() {
        XCTAssertFalse(AlarmShape.location(title: "Studio", isEntering: true).isEditableHere)
    }

    func testRelativeLabels() {
        XCTAssertEqual(AlarmShape.relative(0).label, "At the due time")
        XCTAssertEqual(AlarmShape.relative(-1800).label, "30m before")
        XCTAssertEqual(AlarmShape.relative(-7200).label, "2h before")
        XCTAssertEqual(AlarmShape.relative(-172800).label, "2d before")
    }

    func testLocationLabelNamesTheDirection() {
        XCTAssertEqual(
            AlarmShape.location(title: "Studio", isEntering: true).label, "Arriving at Studio"
        )
        XCTAssertEqual(
            AlarmShape.location(title: "Studio", isEntering: false).label, "Leaving Studio"
        )
    }
}
