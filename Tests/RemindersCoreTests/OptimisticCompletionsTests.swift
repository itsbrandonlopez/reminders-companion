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

    /// The failure this exists to prevent: a completion that never reaches the phone
    /// leaves the task incomplete, so it stays in every fetch — and without an expiry the
    /// row would be hidden for the rest of the session with no way to retry.
    func testAnUnconfirmedCompletionComesBackAfterTheExpiry() {
        var c = OptimisticCompletions()
        let t0 = Date()
        c.markCompleted("a", at: t0)

        // Still within the window and still in the fetch: correctly hidden.
        let midway = t0.addingTimeInterval(OptimisticCompletions.expiry / 2)
        c.reconcile(against: [task("a")], at: midway)
        XCTAssertTrue(c.hides("a", at: midway))

        // Past the window with the task still incomplete: presumed lost, shown again.
        let later = t0.addingTimeInterval(OptimisticCompletions.expiry + 1)
        c.reconcile(against: [task("a")], at: later)
        XCTAssertFalse(c.hides("a", at: later))
        XCTAssertEqual(c.visible(in: [task("a")], at: later).map(\.id), ["a"])
    }

    /// `hides` must expire on its own even if `reconcile` never runs — the watch app can
    /// sit on one fetch for a long time.
    func testHidesExpiresWithoutReconciling() {
        var c = OptimisticCompletions()
        let t0 = Date()
        c.markCompleted("a", at: t0)
        XCTAssertTrue(c.hides("a", at: t0.addingTimeInterval(1)))
        XCTAssertFalse(c.hides("a", at: t0.addingTimeInterval(OptimisticCompletions.expiry + 1)))
    }

    func testReMarkingRestartsTheWindow() {
        var c = OptimisticCompletions()
        let t0 = Date()
        c.markCompleted("a", at: t0)
        let nearlyExpired = t0.addingTimeInterval(OptimisticCompletions.expiry - 1)
        c.markCompleted("a", at: nearlyExpired)
        XCTAssertTrue(c.hides("a", at: nearlyExpired.addingTimeInterval(1)))
    }

    func testReconcilingAgainstAnEmptyFetchClearsEverything() {
        var c = OptimisticCompletions()
        c.markCompleted("a")
        c.markCompleted("b")
        c.reconcile(against: [])
        XCTAssertTrue(c.isEmpty)
    }
}
