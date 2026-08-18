import XCTest
@testable import RemindersCore

final class UndoableActionTests: XCTestCase {

    private func task(_ title: String = "Task") -> TaskItem {
        TaskItem(id: "id-\(title)", title: title, listID: "l", listName: "Work", listColor: .neutral)
    }

    /// The banner reads "<label> “<title>” · Undo", so the label has to describe what
    /// happened rather than what undoing would do.
    func testLabelsDescribeWhatHappened() {
        XCTAssertEqual(UndoableAction.complete(task: task()).label, "Completed")
        XCTAssertEqual(
            UndoableAction.move(task: task(), previousListID: "l", previousListName: "Work").label,
            "Moved from Work"
        )
        XCTAssertEqual(
            UndoableAction.deadline(task: task(), previousDue: nil).label,
            "Deadline changed"
        )
    }

    /// Scheduling something for the first time isn't a "move" — there was nowhere to
    /// move it from.
    func testRescheduleLabelDistinguishesFirstScheduleFromAMove() {
        XCTAssertEqual(
            UndoableAction.reschedule(task: task(), previousDay: nil).label,
            "Scheduled"
        )
        XCTAssertEqual(
            UndoableAction.reschedule(task: task(), previousDay: Day(year: 2026, month: 8, day: 18)).label,
            "Moved"
        )
    }

    func testTaskAccessorReturnsTheSubjectOfEveryCase() {
        let t = task("Pay invoice")
        XCTAssertEqual(UndoableAction.complete(task: t).task.title, "Pay invoice")
        XCTAssertEqual(UndoableAction.reschedule(task: t, previousDay: nil).task.title, "Pay invoice")
        XCTAssertEqual(UndoableAction.deadline(task: t, previousDue: nil).task.title, "Pay invoice")
        XCTAssertEqual(
            UndoableAction.move(task: t, previousListID: "x", previousListName: "y").task.title,
            "Pay invoice"
        )
    }

    /// SwiftUI keys the banner on the action so a new one replaces the old and restarts
    /// its auto-dismiss timer, which needs distinct values to compare unequal.
    func testDistinctActionsAreNotEqual() {
        let t = task()
        XCTAssertNotEqual(
            UndoableAction.reschedule(task: t, previousDay: nil),
            UndoableAction.reschedule(task: t, previousDay: Day(year: 2026, month: 8, day: 18))
        )
        XCTAssertNotEqual(UndoableAction.complete(task: t), UndoableAction.reschedule(task: t, previousDay: nil))
    }
}
