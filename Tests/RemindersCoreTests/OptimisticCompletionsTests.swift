import XCTest
@testable import RemindersCore

final class OptimisticCompletionsTests: XCTestCase {

    private func task(_ id: String) -> TaskItem {
        TaskItem(id: id, title: id, listID: "l", listName: "L", listColor: .neutral)
    }

    func testStartsEmpty() {
        let c = OptimisticCompletions()
        XCTAssertTrue(c.isEmpty)
        XCTAssertFalse(c.hides("a"))
    }

    func testMarkingHidesTheRowImmediately() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        XCTAssertTrue(c.hides("a"))
        XCTAssertEqual(c.visible(in: [task("a"), task("b")]).map(\.id), ["b"])
    }

    /// The task is still in the fetch, meaning the phone has not written yet — so it must
    /// stay hidden, or it would reappear and look like the tap was ignored.
    func testStaysHiddenWhileTheTaskIsStillPresent() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.reconcile(against: [task("a"), task("b")])
        XCTAssertTrue(c.hides("a"))
    }

    /// Once it leaves the incomplete fetch the write landed, and the entry is dead weight.
    func testForgetsOnceTheTaskIsGone() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.reconcile(against: [task("b")])
        XCTAssertFalse(c.hides("a"))
        XCTAssertTrue(c.isEmpty)
    }

    /// Otherwise un-completing the task elsewhere would leave it permanently invisible on
    /// the Watch.
    func testATaskUncompletedElsewhereBecomesVisibleAgain() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.reconcile(against: [task("b")])          // completed — entry dropped
        c.reconcile(against: [task("a"), task("b")]) // came back
        XCTAssertFalse(c.hides("a"))
        XCTAssertEqual(c.visible(in: [task("a"), task("b")]).map(\.id), ["a", "b"])
    }

    func testHandlesSeveralPendingAtOnce() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.markCompleted("b")
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c.visible(in: [task("a"), task("b")]).isEmpty)
        c.reconcile(against: [task("b")])
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c.hides("b"))
    }

    func testMarkingTwiceIsIdempotent() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.markCompleted("a")
        XCTAssertEqual(c.count, 1)
    }

    func testRestoreBringsARowBack() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.restore("a")
        XCTAssertFalse(c.hides("a"))
    }

    func testReconcilingAgainstAnEmptyFetchClearsEverything() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.markCompleted("b")
        c.reconcile(against: [])
        XCTAssertTrue(c.isEmpty)
    }
}
