import XCTest
@testable import RemindersCore

final class BacklogSortTests: XCTestCase {

    private func task(
        _ name: String, due: Day?, priority: Priority = .none
    ) -> TaskItem {
        TaskItem(
            id: name, title: name, listID: "l", listName: "L", listColor: .neutral,
            priority: priority, dueDay: due
        )
    }

    private let aug10 = Day(year: 2026, month: 8, day: 10)
    private let aug14 = Day(year: 2026, month: 8, day: 14)
    private let aug17 = Day(year: 2026, month: 8, day: 17)

    func testOldestFirst() {
        let sorted = BacklogSort.oldestFirst.sort([
            task("mid", due: aug14), task("old", due: aug10), task("new", due: aug17),
        ])
        XCTAssertEqual(sorted.map(\.title), ["old", "mid", "new"])
    }

    func testNewestFirst() {
        let sorted = BacklogSort.newestFirst.sort([
            task("mid", due: aug14), task("old", due: aug10), task("new", due: aug17),
        ])
        XCTAssertEqual(sorted.map(\.title), ["new", "mid", "old"])
    }

    func testSameDayFallsBackToPriorityInBothDirections() {
        let input = [
            task("low", due: aug10, priority: .low),
            task("high", due: aug10, priority: .high),
            task("none", due: aug10),
        ]
        XCTAssertEqual(BacklogSort.oldestFirst.sort(input).map(\.title), ["high", "low", "none"])
        XCTAssertEqual(BacklogSort.newestFirst.sort(input).map(\.title), ["high", "low", "none"])
    }

    func testUndatedItemsSortLastRegardlessOfDirection() {
        let input = [task("undated", due: nil), task("dated", due: aug10)]
        XCTAssertEqual(BacklogSort.oldestFirst.sort(input).map(\.title), ["dated", "undated"])
        XCTAssertEqual(BacklogSort.newestFirst.sort(input).map(\.title), ["dated", "undated"])
    }

    func testPlannedDayWinsOverDueDateForAge() {
        // boardDay is planned-day-first, so a task replanned recently is not "old".
        var replanned = task("replanned", due: aug10)
        replanned.plannedDay = aug17
        let sorted = BacklogSort.oldestFirst.sort([replanned, task("old", due: aug14)])
        XCTAssertEqual(sorted.map(\.title), ["old", "replanned"])
    }

    func testEmptyAndSingle() {
        XCTAssertTrue(BacklogSort.oldestFirst.sort([]).isEmpty)
        XCTAssertEqual(BacklogSort.newestFirst.sort([task("a", due: aug10)]).map(\.title), ["a"])
    }
}
